using GLib;

private errordomain JobError {
    INVALID_REQUEST,
    UNSUPPORTED_OPERATION,
    INVALID_DESTINATION,
    CONFLICT
}

private class Request : Object {
    public int64 id;
    public string op;
    public string? source;
    public string? destination;
    public string policy = "ask";
    public bool policy_once;
    public string[] sources = {};

    public Request (int64 id, string op) {
        this.id = id;
        this.op = op;
    }
}

private class FileJobServer : Object {
    private const uint MAX_QUEUED_JOBS = 16;
    private const string INFO_ATTRIBUTES =
        "standard::type,standard::symlink-target";
    private const string IDENTITY_ATTRIBUTES =
        "id::file,id::filesystem,unix::device,unix::inode";
    private const string DELETE_ATTRIBUTES =
        "standard::name,standard::type,id::filesystem,unix::is-mountpoint";

    // ponytail: One worker and a 16-job FIFO are intentional. Add workers only if measured latency requires it.
    private Queue<Request> jobs = new Queue<Request> ();
    private Mutex jobs_lock;
    private Cond jobs_ready;
    private Mutex output_lock;
    private Thread<bool> worker;
    private Request? active_request;
    private Cancellable? active_cancellable;
    private bool input_closed;

    public FileJobServer () {
        worker = new Thread<bool> ("file-jobs", worker_main);
    }

    public void send_ready () {
        var builder = begin_event ("ready");
        send (builder);
    }

    public void accept (string line) {
        int64? id = null;

        try {
            var parser = new Json.Parser ();
            parser.load_from_data (line);
            unowned Json.Node? root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                throw new JobError.INVALID_REQUEST ("Request must be a JSON object");

            unowned Json.Object? object = root.get_object ();
            if (object == null)
                throw new JobError.INVALID_REQUEST ("Request must be a JSON object");

            id = require_int (object, "id");
            Request request = parse_request (object, id);
            if (request.op == "cancel") {
                cancel (request.id);
                return;
            }

            string? rejection = enqueue (request);
            if (rejection == "duplicate-id")
                send_rejected (request.id, rejection, "Job id is already in use");
            else if (rejection == "queue-full")
                send_rejected (request.id, rejection, "Job queue is full");
        } catch (JobError error) {
            stderr.puts ("file-jobs: rejected invalid request\n");
            stderr.flush ();
            send_rejected (id, error.code == JobError.UNSUPPORTED_OPERATION
                ? "unsupported-op" : "invalid-request", error.message);
        } catch (Error error) {
            stderr.puts ("file-jobs: rejected invalid JSON\n");
            stderr.flush ();
            send_rejected (id, "invalid-json", "Invalid JSON request");
        }
    }

    public void close_input () {
        jobs_lock.lock ();
        input_closed = true;
        jobs_ready.signal ();
        jobs_lock.unlock ();
        worker.join ();
    }

    private Request parse_request (Json.Object object, int64 id) throws JobError {
        string op = require_string (object, "op");
        var request = new Request (id, op);

        switch (op) {
        case "mkdir":
        case "touch":
            request.destination = require_string (object, "destination");
            break;
        case "rename":
            request.source = require_string (object, "source");
            request.destination = require_string (object, "destination");
            break;
        case "copy":
        case "move":
            request.sources = require_sources (object);
            request.destination = require_string (object, "destination");
            request.policy = optional_policy (object);
            request.policy_once = optional_bool (object, "policyOnce");
            break;
        case "trash":
        case "delete":
            request.sources = require_sources (object);
            break;
        case "cancel":
            break;
        default:
            throw new JobError.UNSUPPORTED_OPERATION ("Unsupported operation");
        }

        return request;
    }

    private static int64 require_int (Json.Object object, string name) throws JobError {
        unowned Json.Node? node = object.get_member (name);
        if (node == null || node.get_node_type () != Json.NodeType.VALUE ||
            node.get_value_type () != typeof (int64))
            throw new JobError.INVALID_REQUEST ("id must be an integer");
        return node.get_int ();
    }

    private static string require_string (Json.Object object, string name) throws JobError {
        unowned Json.Node? node = object.get_member (name);
        if (node == null || node.get_node_type () != Json.NodeType.VALUE ||
            node.get_value_type () != typeof (string) || node.get_string () == null ||
            node.get_string ().length == 0)
            throw new JobError.INVALID_REQUEST (name + " must be a non-empty string");
        return node.get_string ();
    }

    private static string[] require_sources (Json.Object object) throws JobError {
        unowned Json.Node? node = object.get_member ("sources");
        if (node == null || node.get_node_type () != Json.NodeType.ARRAY)
            throw new JobError.INVALID_REQUEST ("sources must be a non-empty array");

        unowned Json.Array? array = node.get_array ();
        if (array == null || array.get_length () == 0)
            throw new JobError.INVALID_REQUEST ("sources must be a non-empty array");

        string[] sources = new string[array.get_length ()];
        for (uint i = 0; i < array.get_length (); i++) {
            unowned Json.Node element = array.get_element (i);
            if (element.get_node_type () != Json.NodeType.VALUE ||
                element.get_value_type () != typeof (string) ||
                element.get_string () == null || element.get_string ().length == 0)
                throw new JobError.INVALID_REQUEST ("sources must contain non-empty strings");
            sources[i] = element.get_string ();
        }
        return sources;
    }

    private static string optional_policy (Json.Object object) throws JobError {
        if (!object.has_member ("policy"))
            return "ask";

        string policy = require_string (object, "policy");
        if (policy != "ask" && policy != "skip" &&
            policy != "replace" && policy != "rename")
            throw new JobError.INVALID_REQUEST ("policy must be ask, skip, replace, or rename");
        return policy;
    }

    private static bool optional_bool (Json.Object object, string name) throws JobError {
        if (!object.has_member (name))
            return false;

        unowned Json.Node? node = object.get_member (name);
        if (node == null || node.get_node_type () != Json.NodeType.VALUE ||
            node.get_value_type () != typeof (bool))
            throw new JobError.INVALID_REQUEST (name + " must be a boolean");
        return node.get_boolean ();
    }

    private string? enqueue (Request request) {
        string? rejection = null;
        jobs_lock.lock ();

        if (active_request != null && active_request.id == request.id) {
            rejection = "duplicate-id";
        } else {
            for (uint i = 0; i < jobs.get_length (); i++) {
                if (jobs.peek_nth (i).id == request.id) {
                    rejection = "duplicate-id";
                    break;
                }
            }
        }

        if (rejection == null && jobs.get_length () >= MAX_QUEUED_JOBS)
            rejection = "queue-full";
        if (rejection == null) {
            jobs.push_tail (request);
            jobs_ready.signal ();
        }

        jobs_lock.unlock ();
        return rejection;
    }

    private void cancel (int64 id) {
        Request? queued = null;
        bool found = false;

        jobs_lock.lock ();
        if (active_request != null && active_request.id == id) {
            active_cancellable.cancel ();
            found = true;
        } else {
            for (uint i = 0; i < jobs.get_length (); i++) {
                if (jobs.peek_nth (i).id == id) {
                    queued = jobs.pop_nth (i);
                    found = true;
                    break;
                }
            }
        }
        jobs_lock.unlock ();

        if (queued != null)
            send_finished (queued, "cancelled");
        else if (!found)
            send_rejected (id, "no-such-job", "Job is not active or queued");
    }

    private bool worker_main () {
        while (true) {
            jobs_lock.lock ();
            while (jobs.is_empty () && !input_closed)
                jobs_ready.wait (jobs_lock);
            if (jobs.is_empty () && input_closed) {
                jobs_lock.unlock ();
                return true;
            }

            Request request = jobs.pop_head ();
            var cancellable = new Cancellable ();
            active_request = request;
            active_cancellable = cancellable;
            jobs_lock.unlock ();

            send_started (request);
            string status = "ok";
            string? code = null;
            string? message = null;
            try {
                run (request, cancellable);
            } catch (JobError error) {
                if (error.code == JobError.CONFLICT) {
                    status = "conflict";
                    code = "destination-exists";
                    message = "Destination already exists";
                } else {
                    status = "error";
                    code = "invalid-destination";
                    message = error.message;
                }
            } catch (Error error) {
                if (error is IOError.CANCELLED) {
                    status = "cancelled";
                } else {
                    status = "error";
                    classify_error (error, out code, out message);
                }
            }

            if (status == "error") {
                stderr.printf ("file-jobs: job %" + int64.FORMAT + " failed: %s\n",
                    request.id, code);
                stderr.flush ();
            }
            send_finished (request, status, code, message);

            jobs_lock.lock ();
            active_request = null;
            active_cancellable = null;
            jobs_lock.unlock ();
        }
    }

    private void run (Request request, Cancellable cancellable) throws Error {
        switch (request.op) {
        case "mkdir":
        case "touch":
            run_create (request, cancellable, request.op == "mkdir");
            break;
        case "rename":
            run_rename (request, cancellable);
            break;
        case "copy":
            run_copy_move (request, cancellable, false);
            break;
        case "move":
            run_copy_move (request, cancellable, true);
            break;
        case "trash":
            run_remove (request, cancellable, true);
            break;
        case "delete":
            run_remove (request, cancellable, false);
            break;
        }
    }

    private void run_create (Request request, Cancellable cancellable, bool directory)
        throws Error {
        File file = File.new_for_commandline_arg (request.destination);
        try {
            if (directory) {
                file.make_directory (cancellable);
            } else {
                FileOutputStream stream = file.create (FileCreateFlags.NONE, cancellable);
                stream.close (cancellable);
            }
        } catch (IOError.EXISTS error) {
            raise_conflict (request, file, file);
        }
        send_progress (request, 1, file);
    }

    private void run_rename (Request request, Cancellable cancellable) throws Error {
        File source = File.new_for_commandline_arg (request.source);
        File destination = File.new_for_commandline_arg (request.destination);
        FileInfo info = source.query_info (FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);

        if (info.get_file_type () == FileType.DIRECTORY) {
            File checked_source;
            File checked_destination;
            resolve_guard_paths (source, destination,
                out checked_source, out checked_destination);
            if (checked_source.equal (checked_destination) ||
                checked_destination.has_prefix (checked_source))
                throw new JobError.INVALID_DESTINATION (
                    "A directory cannot be moved into itself or its descendant");
        }
        if (source.equal (destination)) {
            send_progress (request, 1, source);
            return;
        }
        if (exists (destination, cancellable))
            raise_conflict (request, source, destination);

        try {
            source.move (destination, FileCopyFlags.NOFOLLOW_SYMLINKS, cancellable);
        } catch (IOError.EXISTS error) {
            raise_conflict (request, source, destination);
        }
        send_progress (request, 1, destination);
    }

    private void run_copy_move (Request request, Cancellable cancellable, bool move)
        throws Error {
        File destination_directory = File.new_for_commandline_arg (request.destination);
        FileInfo destination_info = destination_directory.query_info (
            FileAttribute.STANDARD_TYPE, FileQueryInfoFlags.NONE, cancellable);
        if (destination_info.get_file_type () != FileType.DIRECTORY)
            throw new IOError.NOT_DIRECTORY ("Destination is not a directory");

        int64 items_done = 0;
        foreach (string value in request.sources) {
            string policy = request.policy;
            if (request.policy_once) {
                request.policy = "ask";
                request.policy_once = false;
            }
            cancellable.set_error_if_cancelled ();
            File source = File.new_for_commandline_arg (value);
            FileInfo source_info = source.query_info (INFO_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            string? basename = source.get_basename ();
            if (basename == null || basename.length == 0)
                throw new JobError.INVALID_DESTINATION ("Source has no usable name");

            File initial_destination = destination_directory.get_child (basename);
            bool is_directory = source_info.get_file_type () == FileType.DIRECTORY;
            File checked_source = source;
            File checked_destination = initial_destination;
            bool same_initial = same_identity (source, initial_destination, cancellable);
            if (is_directory) {
                resolve_guard_paths (source, initial_destination,
                    out checked_source, out checked_destination);
                if (!same_initial &&
                    checked_destination.has_prefix (checked_source))
                    throw new JobError.INVALID_DESTINATION (
                        "A directory cannot be copied or moved into itself or its descendant");
            }
            if (policy == "replace" && (same_initial ||
                (is_directory && checked_source.has_prefix (checked_destination))))
                throw new JobError.INVALID_DESTINATION (
                    "Replacing this destination would delete the source");

            bool destination_exists;
            File? destination = prepare_destination (request, source,
                source_info, initial_destination, policy, cancellable,
                out destination_exists);
            if (destination == null) {
                items_done++;
                send_progress (request, items_done, source);
                continue;
            }
            if (same_identity (source, destination, cancellable))
                throw new JobError.INVALID_DESTINATION (
                    "Source and destination refer to the same file");
            if (is_directory) {
                resolve_guard_paths (source, destination,
                    out checked_source, out checked_destination);
                if (checked_source.equal (checked_destination) ||
                    checked_destination.has_prefix (checked_source) ||
                    (destination_exists && checked_source.has_prefix (checked_destination)))
                    throw new JobError.INVALID_DESTINATION (
                        "A directory cannot be copied or moved into itself or its descendant");
            }

            send_progress (request, items_done, source);
            var created_nodes = new Queue<File> ();
            try {
                if (move)
                    move_tree (source, destination, cancellable, destination_exists);
                else
                    copy_tree (request, source, destination, cancellable, items_done,
                        destination_exists, false, created_nodes);
            } catch (IOError.EXISTS error) {
                remove_created_nodes (created_nodes);
                if (policy == "skip") {
                    items_done++;
                    send_progress (request, items_done, source);
                    continue;
                }
                raise_conflict (request, source, destination);
            } catch (Error error) {
                remove_created_nodes (created_nodes);
                throw error;
            }
            items_done++;
            send_progress (request, items_done, destination);
        }
    }

    private File? prepare_destination (Request request, File source, FileInfo source_info,
        File destination, string policy, Cancellable cancellable,
        out bool destination_exists) throws Error {
        destination_exists = false;
        if (!exists (destination, cancellable)) {
            return destination;
        }

        switch (policy) {
        case "ask":
            raise_conflict (request, source, destination);
            break;
        case "skip":
            return null;
        case "replace":
            FileInfo destination_info = destination.query_info (FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            ensure_same_type (source_info, destination_info);
            if (same_identity (source, destination, cancellable))
                throw new JobError.INVALID_DESTINATION (
                    "Source and destination refer to the same file");
            destination_exists = true;
            return destination;
        case "rename":
            File? parent = destination.get_parent ();
            string? name = destination.get_basename ();
            if (parent == null || name == null)
                throw new JobError.INVALID_DESTINATION ("Destination has no usable name");
            return unique_destination (parent, name,
                source_info.get_file_type () == FileType.DIRECTORY, cancellable);
        }
        return null;
    }

    private File unique_destination (File parent, string name, bool is_directory,
        Cancellable cancellable) throws Error {
        int dot = is_directory ? -1 : name.last_index_of (".");
        if (dot == 0)
            dot = -1;
        string stem = dot > 0 ? name.substring (0, dot) : name;
        string extension = dot > 0 ? name.substring (dot) : "";

        for (int number = 1; ; number++) {
            File candidate = parent.get_child ("%s (copy %d)%s".printf (
                stem, number, extension));
            if (!exists (candidate, cancellable))
                return candidate;
        }
    }

    private void copy_tree (Request request, File source, File destination,
        Cancellable cancellable, int64 items_done, bool destination_exists,
        bool track_created, Queue<File> created_nodes) throws Error {
        cancellable.set_error_if_cancelled ();
        FileInfo info = source.query_info (INFO_ATTRIBUTES,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);

        if (destination_exists) {
            FileInfo destination_info = destination.query_info (FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            ensure_same_type (info, destination_info);
            if (same_identity (source, destination, cancellable))
                throw new JobError.INVALID_DESTINATION (
                    "Source and destination refer to the same file");
            if (info.get_file_type () == FileType.DIRECTORY) {
                File checked_source;
                File checked_destination;
                resolve_guard_paths (source, destination,
                    out checked_source, out checked_destination);
                if (checked_source.equal (checked_destination) ||
                    checked_destination.has_prefix (checked_source) ||
                    checked_source.has_prefix (checked_destination))
                    throw new JobError.INVALID_DESTINATION (
                        "Source and destination directories overlap");
                FileEnumerator children = source.enumerate_children (
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
                FileInfo? child;
                while ((child = children.next_file (cancellable)) != null) {
                    string name = child.get_name ();
                    File child_destination = destination.get_child (name);
                    copy_tree (request, source.get_child (name), child_destination,
                        cancellable, items_done, exists (child_destination, cancellable),
                        true, created_nodes);
                }
                children.close (cancellable);
                copy_metadata (source, destination, cancellable);
                return;
            }
            replace_leaf (source, info, destination, cancellable);
            return;
        }

        bool created = false;
        try {
            if (info.get_file_type () == FileType.DIRECTORY) {
                destination.make_directory (cancellable);
                created = true;
                FileEnumerator children = source.enumerate_children (
                    FileAttribute.STANDARD_NAME,
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
                FileInfo? child;
                while ((child = children.next_file (cancellable)) != null) {
                    string name = child.get_name ();
                    copy_tree (request, source.get_child (name), destination.get_child (name),
                        cancellable, items_done, false, false, created_nodes);
                }
                children.close (cancellable);
                copy_metadata (source, destination, cancellable);
            } else if (info.get_file_type () == FileType.SYMBOLIC_LINK) {
                copy_symlink (info, destination, cancellable);
                created = true;
            } else {
                source.copy (destination,
                    FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS,
                    cancellable);
                created = true;
            }
        } catch (IOError.EXISTS error) {
            if (created)
                remove_partial_destination (destination);
            throw error;
        } catch (Error error) {
            remove_partial_destination (destination);
            throw error;
        }

        if (track_created && !destination_exists)
            created_nodes.push_tail (destination);
    }

    private void replace_leaf (File source, FileInfo source_info, File destination,
        Cancellable cancellable) throws Error {
        File? parent = destination.get_parent ();
        if (parent == null)
            throw new JobError.INVALID_DESTINATION ("Destination has no parent");

        File staging = parent.get_child (".dms-files-stage-" + Uuid.string_random ());
        bool copied = false;
        try {
            if (source_info.get_file_type () == FileType.SYMBOLIC_LINK)
                copy_symlink (source_info, staging, cancellable);
            else
                source.copy (staging,
                    FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS,
                    cancellable);
            copied = true;
            cancellable.set_error_if_cancelled ();

            FileInfo destination_info = destination.query_info (FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            ensure_same_type (source_info, destination_info);
            if (same_identity (source, destination, cancellable))
                throw new JobError.INVALID_DESTINATION (
                    "Source and destination refer to the same file");
            staging.move (destination,
                FileCopyFlags.OVERWRITE |
                FileCopyFlags.NO_FALLBACK_FOR_MOVE |
                FileCopyFlags.NOFOLLOW_SYMLINKS,
                cancellable);
            copied = false;
        } catch (Error error) {
            if (copied || !(error is IOError.EXISTS))
                remove_staging (staging);
            throw error;
        }
    }

    private void move_tree (File source, File destination, Cancellable cancellable,
        bool destination_exists) throws Error {
        cancellable.set_error_if_cancelled ();
        FileInfo source_info = source.query_info (INFO_ATTRIBUTES,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        if (!destination_exists) {
            try {
                source.move (destination, FileCopyFlags.NOFOLLOW_SYMLINKS, cancellable);
                return;
            } catch (IOError.NOT_SUPPORTED error) {
                if (source_info.get_file_type () != FileType.DIRECTORY)
                    throw error;
            } catch (IOError.WOULD_RECURSE error) {
                if (source_info.get_file_type () != FileType.DIRECTORY)
                    throw error;
            }
            destination.make_directory (cancellable);
        }

        FileInfo destination_info = destination.query_info (FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        ensure_same_type (source_info, destination_info);
        if (same_identity (source, destination, cancellable))
            throw new JobError.INVALID_DESTINATION (
                "Source and destination refer to the same file");

        if (source_info.get_file_type () != FileType.DIRECTORY) {
            source.move (destination,
                FileCopyFlags.OVERWRITE | FileCopyFlags.NOFOLLOW_SYMLINKS,
                cancellable);
            return;
        }

        File checked_source;
        File checked_destination;
        resolve_guard_paths (source, destination,
            out checked_source, out checked_destination);
        if (checked_source.equal (checked_destination) ||
            checked_destination.has_prefix (checked_source) ||
            checked_source.has_prefix (checked_destination))
            throw new JobError.INVALID_DESTINATION (
                "Source and destination directories overlap");

        string[] names = {};
        FileEnumerator children = source.enumerate_children (FileAttribute.STANDARD_NAME,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        FileInfo? child;
        while ((child = children.next_file (cancellable)) != null)
            names += child.get_name ();
        children.close (cancellable);

        foreach (string name in names) {
            File child_source = source.get_child (name);
            File child_destination = destination.get_child (name);
            move_tree (child_source, child_destination, cancellable,
                exists (child_destination, cancellable));
        }
        copy_metadata (source, destination, cancellable);
        source.delete (cancellable);
    }

    private static void copy_symlink (FileInfo source_info, File destination,
        Cancellable cancellable) throws Error {
        string? target = source_info.get_symlink_target ();
        if (target == null)
            throw new IOError.INVALID_DATA ("Symbolic link has no target");
        destination.make_symbolic_link (target, cancellable);
    }

    private static void ensure_same_type (FileInfo source, FileInfo destination)
        throws JobError {
        if (source.get_file_type () != destination.get_file_type ())
            throw new JobError.INVALID_DESTINATION (
                "Replacing an item with a different type is not allowed");
    }

    private static void copy_metadata (File source, File destination,
        Cancellable cancellable) throws Error {
        try {
            source.copy_attributes (destination,
                FileCopyFlags.ALL_METADATA | FileCopyFlags.NOFOLLOW_SYMLINKS, cancellable);
        } catch (IOError.NOT_SUPPORTED error) {
            try {
                source.copy_attributes (destination,
                    FileCopyFlags.NOFOLLOW_SYMLINKS, cancellable);
            } catch (IOError.NOT_SUPPORTED fallback_error) {
                // This backend cannot set metadata for this file type.
            }
        }
    }

    private void remove_partial_destination (File destination) {
        var cleanup = new Cancellable ();
        try {
            if (exists (destination, cleanup))
                delete_tree (destination, cleanup);
        } catch (Error error) {
            stderr.puts ("file-jobs: failed to remove a partial destination\n");
            stderr.flush ();
        }
    }

    private void remove_created_nodes (Queue<File> created_nodes) {
        while (!created_nodes.is_empty ())
            remove_partial_destination (created_nodes.pop_tail ());
    }

    private void remove_staging (File staging) {
        try {
            staging.delete (new Cancellable ());
        } catch (IOError.NOT_FOUND error) {
            return;
        } catch (Error error) {
            stderr.puts ("file-jobs: failed to remove a staging file\n");
            stderr.flush ();
        }
    }

    private static bool same_identity (File source, File destination,
        Cancellable cancellable) throws Error {
        if (source.equal (destination))
            return true;

        FileInfo source_info = source.query_info (IDENTITY_ATTRIBUTES,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        FileInfo destination_info;
        try {
            destination_info = destination.query_info (IDENTITY_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        } catch (IOError.NOT_FOUND error) {
            return false;
        }

        unowned string? source_file_id = source_info.get_attribute_string (
            FileAttribute.ID_FILE);
        unowned string? source_filesystem_id = source_info.get_attribute_string (
            FileAttribute.ID_FILESYSTEM);
        unowned string? destination_file_id = destination_info.get_attribute_string (
            FileAttribute.ID_FILE);
        unowned string? destination_filesystem_id = destination_info.get_attribute_string (
            FileAttribute.ID_FILESYSTEM);
        if (source_file_id != null && source_filesystem_id != null &&
            destination_file_id != null && destination_filesystem_id != null &&
            source_file_id == destination_file_id &&
            source_filesystem_id == destination_filesystem_id)
            return true;

        return source_info.has_attribute (FileAttribute.UNIX_DEVICE) &&
            source_info.has_attribute (FileAttribute.UNIX_INODE) &&
            destination_info.has_attribute (FileAttribute.UNIX_DEVICE) &&
            destination_info.has_attribute (FileAttribute.UNIX_INODE) &&
            source_info.get_attribute_uint32 (FileAttribute.UNIX_DEVICE) ==
                destination_info.get_attribute_uint32 (FileAttribute.UNIX_DEVICE) &&
            source_info.get_attribute_uint64 (FileAttribute.UNIX_INODE) ==
                destination_info.get_attribute_uint64 (FileAttribute.UNIX_INODE);
    }

    private static void resolve_guard_paths (File source, File destination,
        out File checked_source, out File checked_destination) throws JobError {
        checked_source = source;
        checked_destination = destination;
        if (!source.is_native () || !destination.is_native ())
            return;

        string? source_path = source.get_path ();
        File? destination_parent = destination.get_parent ();
        string? parent_path = destination_parent == null
            ? null : destination_parent.get_path ();
        string? destination_name = destination.get_basename ();
        if (source_path == null || parent_path == null || destination_name == null)
            throw new JobError.INVALID_DESTINATION ("Cannot resolve local paths safely");

        string? physical_source = Posix.realpath (source_path);
        string? physical_parent = Posix.realpath (parent_path);
        if (physical_source == null || physical_parent == null)
            throw new JobError.INVALID_DESTINATION ("Cannot resolve local paths safely");

        checked_source = File.new_for_path (physical_source);
        checked_destination = File.new_for_path (
            Path.build_filename (physical_parent, destination_name));
    }

    private void run_remove (Request request, Cancellable cancellable, bool trash)
        throws Error {
        int64 items_done = 0;
        foreach (string value in request.sources) {
            cancellable.set_error_if_cancelled ();
            File source = File.new_for_commandline_arg (value);
            send_progress (request, items_done, source);
            if (trash)
                source.trash (cancellable);
            else
                delete_tree (source, cancellable);
            items_done++;
            send_progress (request, items_done, source);
        }
    }

    private void delete_tree (File file, Cancellable cancellable) throws Error {
        cancellable.set_error_if_cancelled ();
        FileInfo info = file.query_info (DELETE_ATTRIBUTES,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
        string? filesystem_id = info.get_attribute_string (FileAttribute.ID_FILESYSTEM);
        string[] mount_points = read_mount_points (file);
        delete_tree_on_filesystem (file, info, filesystem_id, mount_points, cancellable);
    }

    private void delete_tree_on_filesystem (File file, FileInfo info,
        string? filesystem_id, string[] mount_points, Cancellable cancellable) throws Error {
        cancellable.set_error_if_cancelled ();
        string? current_filesystem_id = info.get_attribute_string (
            FileAttribute.ID_FILESYSTEM);
        if (is_mount_point (file, info, mount_points) ||
            (filesystem_id != null && current_filesystem_id != null &&
            filesystem_id != current_filesystem_id))
            throw new JobError.INVALID_DESTINATION (
                "Refusing to recursively delete across a filesystem mount");

        if (info.get_file_type () == FileType.DIRECTORY) {
            FileEnumerator children = file.enumerate_children (DELETE_ATTRIBUTES,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            FileInfo? child;
            while ((child = children.next_file (cancellable)) != null)
                delete_tree_on_filesystem (file.get_child (child.get_name ()), child,
                    filesystem_id, mount_points, cancellable);
            children.close (cancellable);
        }
        file.delete (cancellable);
    }

    private static string[] read_mount_points (File file) throws Error {
        string[] mount_points = {};
        if (!file.is_native ())
            return mount_points;

        string contents;
        FileUtils.get_contents ("/proc/self/mountinfo", out contents);
        foreach (string line in contents.split ("\n")) {
            string[] fields = line.split (" ");
            if (fields.length > 4)
                mount_points += fields[4]
                    .replace ("\\040", " ")
                    .replace ("\\011", "\t")
                    .replace ("\\012", "\n")
                    .replace ("\\134", "\\");
        }
        return mount_points;
    }

    private static bool is_mount_point (File file, FileInfo info,
        string[] mount_points) throws JobError {
        if (info.get_file_type () == FileType.SYMBOLIC_LINK)
            return false;
        if (info.has_attribute (FileAttribute.UNIX_IS_MOUNTPOINT) &&
            info.get_attribute_boolean (FileAttribute.UNIX_IS_MOUNTPOINT))
            return true;
        if (!file.is_native ())
            return false;

        string? path = file.get_path ();
        string? physical_path = path == null ? null : Posix.realpath (path);
        if (physical_path == null)
            throw new JobError.INVALID_DESTINATION ("Cannot resolve local paths safely");
        foreach (string mount_point in mount_points) {
            if (mount_point == physical_path)
                return true;
        }
        return false;
    }

    private static bool exists (File file, Cancellable cancellable) throws Error {
        try {
            file.query_info (FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, cancellable);
            return true;
        } catch (IOError.NOT_FOUND error) {
            return false;
        }
    }

    private void raise_conflict (Request request, File source, File destination)
        throws JobError {
        var builder = begin_event ("conflict", request);
        add_string (builder, "source", source.get_uri ());
        add_string (builder, "destination", destination.get_uri ());
        send (builder);
        throw new JobError.CONFLICT ("Destination already exists");
    }

    private static void classify_error (Error error, out string code, out string message) {
        if (error is IOError.NOT_FOUND) {
            code = "not-found";
            message = "File not found";
        } else if (error is IOError.EXISTS) {
            code = "destination-exists";
            message = "Destination already exists";
        } else if (error is IOError.PERMISSION_DENIED) {
            code = "permission-denied";
            message = "Permission denied";
        } else if (error is IOError.NOT_DIRECTORY) {
            code = "not-directory";
            message = "A path component is not a directory";
        } else if (error is IOError.IS_DIRECTORY) {
            code = "is-directory";
            message = "Expected a file";
        } else if (error is IOError.NO_SPACE) {
            code = "no-space";
            message = "Not enough space";
        } else if (error is IOError.READ_ONLY) {
            code = "read-only";
            message = "Filesystem is read-only";
        } else if (error is IOError.NOT_SUPPORTED) {
            code = "not-supported";
            message = "Operation is not supported";
        } else if (error is IOError.BUSY) {
            code = "busy";
            message = "File is busy";
        } else {
            code = "failed";
            message = "Filesystem operation failed";
        }
    }

    private Json.Builder begin_event (string name, Request? request = null) {
        var builder = new Json.Builder ();
        builder.begin_object ();
        add_string (builder, "event", name);
        if (request != null) {
            add_int (builder, "id", request.id);
            add_string (builder, "job", request.op);
        }
        return builder;
    }

    private void send_started (Request request) {
        send (begin_event ("started", request));
    }

    private void send_progress (Request request, int64 items_done, File current) {
        var builder = begin_event ("progress", request);
        add_int (builder, "itemsDone", items_done);
        add_int (builder, "itemsTotal",
            request.sources.length > 0 ? request.sources.length : 1);
        add_string (builder, "current", current.get_uri ());
        send (builder);
    }

    private void send_finished (Request request, string status, string? code = null,
        string? message = null) {
        var builder = begin_event ("finished", request);
        add_string (builder, "status", status);
        if (status == "cancelled") {
            code = "cancelled";
            message = "Operation was cancelled";
        }
        if (code != null)
            add_string (builder, "code", code);
        if (message != null)
            add_string (builder, "message", message);
        send (builder);
    }

    private void send_rejected (int64? id, string code, string message) {
        var builder = begin_event ("rejected");
        if (id != null)
            add_int (builder, "id", id);
        add_string (builder, "status", "error");
        add_string (builder, "code", code);
        add_string (builder, "message", message);
        send (builder);
    }

    private static void add_string (Json.Builder builder, string name, string value) {
        builder.set_member_name (name);
        builder.add_string_value (value);
    }

    private static void add_int (Json.Builder builder, string name, int64 value) {
        builder.set_member_name (name);
        builder.add_int_value (value);
    }

    private void send (Json.Builder builder) {
        builder.end_object ();
        Json.Node? root = builder.get_root ();
        if (root == null)
            return;
        var generator = new Json.Generator ();
        generator.set_root (root);
        size_t length;
        string data = generator.to_data (out length);

        output_lock.lock ();
        stdout.puts (data);
        stdout.putc ('\n');
        stdout.flush ();
        output_lock.unlock ();
    }
}

public static int main () {
    var server = new FileJobServer ();
    server.send_ready ();

    string? line;
    while ((line = stdin.read_line ()) != null)
        server.accept (line);

    server.close_input ();
    return 0;
}
