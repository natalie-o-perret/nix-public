pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    property string lastOutput: ""
    property var sigilWindow: null
    property var navigationState: null
    property double lastMonitorChangeMs: 0

    function screenForOutput(output) {
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === output)
                return Quickshell.screens[i];
        }
        return null;
    }

    function showEffect(output, effectType, direction) {
        const target = screenForOutput(output);
        if (!target)
            return false;

        if (sigilWindow) {
            sigilWindow.destroy();
            sigilWindow = null;
        }

        sigilWindow = sigilWindowComponent.createObject(root, {
            "screen": target,
            "effectType": effectType,
            "direction": direction || ""
        });
        if (!sigilWindow) {
            console.warn("[MonitorSigils] Failed to create overlay for", output);
            return false;
        }
        return true;
    }

    function bloom(output) {
        return showEffect(output, "portal", "");
    }

    function sweep(output, direction) {
        return showEffect(output, "direction", direction);
    }

    function focusedState() {
        let workspace = null;
        for (let i = 0; i < NiriService.allWorkspaces.length; i++) {
            const candidate = NiriService.allWorkspaces[i];
            if (String(candidate.id) === String(NiriService.focusedWorkspaceId) || candidate.is_focused) {
                workspace = candidate;
                break;
            }
        }
        if (!workspace)
            return null;

        let focusedWindow = null;
        for (let i = 0; i < NiriService.windows.length; i++) {
            if (NiriService.windows[i].is_focused) {
                focusedWindow = NiriService.windows[i];
                break;
            }
        }

        let column = null;
        let row = null;
        if (focusedWindow && String(focusedWindow.workspace_id) === String(workspace.id)) {
            const position = focusedWindow.layout?.pos_in_scrolling_layout;
            if (position && position.length >= 2) {
                column = position[0];
                row = position[1];
            }
        }

        return {
            "output": workspace.output || NiriService.currentOutput,
            "workspaceId": String(workspace.id),
            "workspaceIndex": workspace.idx,
            "windowId": focusedWindow ? String(focusedWindow.id) : "",
            "column": column,
            "row": row
        };
    }

    function updateNavigationState() {
        const next = focusedState();
        if (!next)
            return;

        const previous = navigationState;
        navigationState = next;
        if (!previous || next.output !== previous.output || Date.now() - lastMonitorChangeMs < 100)
            return;

        let direction = "";
        if (next.workspaceId !== previous.workspaceId) {
            if (next.workspaceIndex > previous.workspaceIndex)
                direction = "down";
            else if (next.workspaceIndex < previous.workspaceIndex)
                direction = "up";
        } else if (next.column !== null && previous.column !== null) {
            const horizontal = next.column - previous.column;
            const vertical = next.row - previous.row;
            if (Math.abs(horizontal) >= Math.abs(vertical) && horizontal !== 0)
                direction = horizontal > 0 ? "right" : "left";
            else if (vertical !== 0)
                direction = vertical > 0 ? "down" : "up";
        }

        if (direction)
            sweep(next.output, direction);
    }

    function outputChanged(output) {
        if (!output)
            return;
        if (!lastOutput) {
            lastOutput = output;
            return;
        }
        if (output === lastOutput)
            return;

        lastOutput = output;
        lastMonitorChangeMs = Date.now();
        bloom(output);
    }

    Timer {
        id: outputChangeTimer
        interval: 0
        onTriggered: root.outputChanged(NiriService.currentOutput)
    }

    Timer {
        id: navigationChangeTimer
        interval: 0
        onTriggered: root.updateNavigationState()
    }

    Connections {
        target: NiriService

        function onCurrentOutputChanged() {
            outputChangeTimer.restart();
            navigationChangeTimer.restart();
        }

        function onFocusedWorkspaceIdChanged() {
            outputChangeTimer.restart();
            navigationChangeTimer.restart();
        }

        function onWindowsChanged() {
            navigationChangeTimer.restart();
        }

        function onWorkspacesChanged() {
            navigationChangeTimer.restart();
        }
    }

    IpcHandler {
        target: "monitor-sigils"

        function bloom(): string {
            return root.bloom(NiriService.currentOutput) ? "OK" : "ERROR";
        }

        function direction(direction: string): string {
            if (!["left", "right", "up", "down"].includes(direction))
                return "ERROR: expected left, right, up, or down";
            return root.sweep(NiriService.currentOutput, direction) ? "OK" : "ERROR";
        }

        function status(): string {
            return "current=" + NiriService.currentOutput + " last=" + root.lastOutput + " visible=" + (root.sigilWindow !== null);
        }
    }

    Component.onCompleted: {
        root.lastOutput = NiriService.currentOutput;
        root.navigationState = root.focusedState();
    }
    Component.onDestruction: {
        if (root.sigilWindow)
            root.sigilWindow.destroy();
    }

    Component {
        id: sigilWindowComponent

        PanelWindow {
            id: sigils

            property real phase: 0
            property string effectType: "portal"
            property string direction: ""

            visible: true
            color: "transparent"

            WlrLayershell.namespace: "dms:monitor-sigils"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {}

            Canvas {
                id: canvas

                anchors.fill: parent
                antialiasing: true

                function fract(value) {
                    return value - Math.floor(value);
                }

                function random(seed) {
                    return fract(Math.sin(seed * 12.9898) * 43758.5453);
                }

                function easeOutCubic(value) {
                    return 1 - Math.pow(1 - value, 3);
                }

                function smootherstep(value) {
                    const t = Math.max(0, Math.min(1, value));
                    return t * t * t * (t * (t * 6 - 15) + 10);
                }

                function envelope(value) {
                    return smootherstep(value / 0.12) * (1 - smootherstep((value - 0.78) / 0.22));
                }

                function directionEnvelope(value) {
                    return smootherstep(value / 0.04) * (1 - smootherstep((value - 0.84) / 0.16));
                }

                function drawAngularRose(ctx, radius, alpha) {
                    ctx.save();
                    ctx.rotate(-sigils.phase * 0.9);
                    ctx.globalAlpha = alpha * 0.72;
                    ctx.strokeStyle = "rgba(255, 173, 203, 0.96)";
                    ctx.fillStyle = "rgba(166, 15, 70, 0.14)";
                    ctx.lineWidth = 1.4;

                    for (let i = 0; i < 5; i++) {
                        ctx.save();
                        ctx.rotate(i * Math.PI * 2 / 5);
                        ctx.beginPath();
                        ctx.moveTo(0, -radius * 0.1);
                        ctx.lineTo(-radius * 0.16, -radius * 0.34);
                        ctx.lineTo(0, -radius * 0.7);
                        ctx.lineTo(radius * 0.16, -radius * 0.34);
                        ctx.closePath();
                        ctx.fill();
                        ctx.stroke();
                        ctx.restore();
                    }

                    ctx.beginPath();
                    for (let i = 0; i <= 28; i++) {
                        const angle = i * 0.5;
                        const spiralRadius = radius * 0.012 * i;
                        const x = Math.cos(angle) * spiralRadius;
                        const y = Math.sin(angle) * spiralRadius;
                        if (i === 0)
                            ctx.moveTo(x, y);
                        else
                            ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                    ctx.restore();
                }

                function drawBrokenRing(ctx, radius, alpha) {
                    ctx.save();
                    ctx.rotate(sigils.phase * 1.8);
                    for (let layer = 0; layer < 3; layer++) {
                        const ringRadius = radius + (layer - 1) * 7;
                        ctx.globalAlpha = alpha * (0.34 + layer * 0.15);
                        ctx.strokeStyle = layer === 1 ? "rgba(255, 112, 163, 0.98)" : "rgba(190, 18, 77, 0.72)";
                        ctx.lineWidth = layer === 1 ? 2.2 : 1.2;
                        for (let segment = 0; segment < 12; segment++) {
                            const start = segment * Math.PI / 6 + random(segment + layer * 31) * 0.08;
                            const span = 0.25 + random(segment + layer * 47) * 0.16;
                            ctx.beginPath();
                            ctx.arc(0, 0, ringRadius, start, start + span);
                            ctx.stroke();
                        }
                    }
                    ctx.restore();
                }

                function drawParticles(ctx, radius, alpha) {
                    const count = 92;
                    for (let i = 0; i < count; i++) {
                        const noise = random(i + 10);
                        const angle = i * Math.PI * 2 / count + (random(i + 90) - 0.5) * 0.11 + sigils.phase * (0.28 + noise * 0.48);
                        const distance = radius + (random(i + 170) - 0.5) * 22 + sigils.phase * (12 + noise * 48);
                        const x = Math.cos(angle) * distance;
                        const y = Math.sin(angle) * distance;
                        const size = 1 + random(i + 250) * 2.8;
                        const flicker = 0.35 + Math.abs(Math.sin(sigils.phase * 31 + i * 1.7)) * 0.65;
                        const particleAlpha = alpha * flicker * (0.36 + noise * 0.5);
                        const colour = i % 7 === 0 ? "255, 220, 232" : (i % 3 === 0 ? "255, 76, 139" : "233, 30, 99");

                        ctx.fillStyle = "rgba(" + colour + ", " + (particleAlpha * 0.22) + ")";
                        ctx.beginPath();
                        ctx.arc(x, y, size * 2.5, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.fillStyle = "rgba(" + colour + ", " + particleAlpha + ")";
                        ctx.beginPath();
                        ctx.arc(x, y, size, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }

                function drawSparks(ctx, radius, alpha) {
                    ctx.save();
                    ctx.lineCap = "round";
                    for (let i = 0; i < 20; i++) {
                        const angle = i * Math.PI * 2 / 20 + random(i + 400) * 0.19 - sigils.phase * 0.35;
                        const travel = sigils.phase * (24 + random(i + 440) * 58);
                        const start = radius * (0.78 + random(i + 480) * 0.28) + travel;
                        const length = 5 + random(i + 520) * 13;
                        ctx.globalAlpha = alpha * (0.25 + random(i + 560) * 0.58);
                        ctx.strokeStyle = i % 4 === 0 ? "rgba(255, 226, 235, 0.96)" : "rgba(255, 63, 128, 0.9)";
                        ctx.lineWidth = 0.8 + random(i + 600) * 1.5;
                        ctx.beginPath();
                        ctx.moveTo(Math.cos(angle) * start, Math.sin(angle) * start);
                        ctx.lineTo(Math.cos(angle) * (start + length), Math.sin(angle) * (start + length));
                        ctx.stroke();
                    }
                    ctx.restore();
                }

                function drawFlameTongue(ctx, x, y, angle, length, width, alpha, bright) {
                    const flicker = Math.sin(sigils.phase * 58 + angle * 9 + x * 0.013 + y * 0.017);
                    const curl = Math.sin(sigils.phase * 43 + angle * 13 + x * 0.021 - y * 0.009);
                    const animatedLength = length * (0.84 + (flicker + 1) * 0.12);
                    const animatedWidth = width * (0.88 + (curl + 1) * 0.09);
                    const dx = Math.cos(angle);
                    const dy = Math.sin(angle);
                    const px = -dy;
                    const py = dx;
                    const sway = curl * animatedWidth * 0.72;
                    const tipX = x + dx * animatedLength + px * sway;
                    const tipY = y + dy * animatedLength + py * sway;

                    ctx.save();
                    ctx.globalAlpha = alpha;
                    ctx.beginPath();
                    ctx.moveTo(x + px * animatedWidth * 0.5, y + py * animatedWidth * 0.5);
                    ctx.bezierCurveTo(x + dx * animatedLength * 0.3 + px * animatedWidth * (0.65 + curl * 0.14),
                        y + dy * animatedLength * 0.3 + py * animatedWidth * (0.65 + curl * 0.14),
                        tipX + px * animatedWidth * 0.18, tipY + py * animatedWidth * 0.18, tipX, tipY);
                    ctx.bezierCurveTo(tipX - px * animatedWidth * 0.2, tipY - py * animatedWidth * 0.2,
                        x + dx * animatedLength * 0.22 - px * animatedWidth * (0.62 - curl * 0.12),
                        y + dy * animatedLength * 0.22 - py * animatedWidth * (0.62 - curl * 0.12),
                        x - px * animatedWidth * 0.5, y - py * animatedWidth * 0.5);
                    ctx.closePath();

                    const flame = ctx.createLinearGradient(x, y, tipX, tipY);
                    if (bright) {
                        flame.addColorStop(0, "rgba(255, 238, 255, 1)");
                        flame.addColorStop(0.4, "rgba(213, 105, 255, 1)");
                        flame.addColorStop(1, "rgba(112, 24, 198, 0.18)");
                    } else {
                        flame.addColorStop(0, "rgba(195, 84, 255, 1)");
                        flame.addColorStop(0.5, "rgba(133, 40, 216, 0.98)");
                        flame.addColorStop(1, "rgba(76, 17, 133, 0.2)");
                    }
                    ctx.fillStyle = flame;
                    ctx.fill();
                    ctx.restore();
                }

                function drawFireballCore(ctx, x, y, radius, alpha) {
                    const glow = ctx.createRadialGradient(x, y, 0, x, y, radius * 2.2);
                    glow.addColorStop(0, "rgba(247, 226, 255, " + (alpha * 0.98) + ")");
                    glow.addColorStop(0.2, "rgba(214, 126, 255, " + (alpha * 0.95) + ")");
                    glow.addColorStop(0.48, "rgba(151, 48, 236, " + (alpha * 0.82) + ")");
                    glow.addColorStop(1, "rgba(76, 16, 140, 0)");
                    ctx.fillStyle = glow;
                    ctx.beginPath();
                    ctx.arc(x, y, radius * 2.2, 0, Math.PI * 2);
                    ctx.fill();

                    const core = ctx.createRadialGradient(x - radius * 0.23, y - radius * 0.3, 0, x, y, radius);
                    core.addColorStop(0, "rgba(255, 255, 255, " + alpha + ")");
                    core.addColorStop(0.3, "rgba(238, 204, 255, " + alpha + ")");
                    core.addColorStop(0.7, "rgba(180, 74, 248, " + (alpha * 0.96) + ")");
                    core.addColorStop(1, "rgba(91, 21, 164, " + (alpha * 0.82) + ")");
                    ctx.fillStyle = core;
                    ctx.beginPath();
                    ctx.arc(x, y, radius, 0, Math.PI * 2);
                    ctx.fill();
                }

                function drawOrbitalFireball(ctx, radius, alpha) {
                    const orbitAngle = -Math.PI / 2 + sigils.phase * Math.PI * 2 * 1.3;
                    const orbitRadius = radius * 1.16;
                    const headX = Math.cos(orbitAngle) * orbitRadius;
                    const headY = Math.sin(orbitAngle) * orbitRadius;
                    const headRadius = 13 + Math.sin(sigils.phase * 43) * 1.8;
                    const tailDirection = orbitAngle - Math.PI / 2;

                    for (let i = 22; i >= 1; i--) {
                        const trail = i / 22;
                        const angle = orbitAngle - trail * 1.05;
                        const trailRadius = orbitRadius - trail * 7 + (random(i + 700) - 0.5) * 5;
                        const x = Math.cos(angle) * trailRadius;
                        const y = Math.sin(angle) * trailRadius;
                        const size = 1.2 + (1 - trail) * 5.5;
                        const trailAlpha = alpha * Math.pow(1 - trail, 1.45);

                        ctx.fillStyle = i % 4 === 0 ? "rgba(238, 190, 255, " + trailAlpha + ")" : "rgba(187, 72, 255, " + trailAlpha + ")";
                        ctx.beginPath();
                        ctx.arc(x, y, size, 0, Math.PI * 2);
                        ctx.fill();
                    }

                    for (let i = 0; i < 6; i++) {
                        const jitter = (random(i + 740) - 0.5) * 0.72;
                        const offset = (random(i + 770) - 0.5) * headRadius;
                        drawFlameTongue(ctx, headX - Math.sin(tailDirection) * offset, headY + Math.cos(tailDirection) * offset,
                            tailDirection + jitter, 22 + random(i + 800) * 27, 7 + random(i + 830) * 8,
                            alpha * (0.48 + random(i + 860) * 0.42), i % 3 === 0);
                    }
                    drawFireballCore(ctx, headX, headY, headRadius, alpha);
                }

                function drawEdgeFireball(ctx, x, y, moveX, moveY, alpha, seed) {
                    const tailAngle = Math.atan2(-moveY, -moveX);
                    const normalX = -moveY;
                    const normalY = moveX;

                    for (let i = 12; i >= 1; i--) {
                        const distance = 12 + i * 9;
                        const jitter = (random(seed + i * 7) - 0.5) * 24;
                        const emberX = x - moveX * distance + normalX * jitter;
                        const emberY = y - moveY * distance + normalY * jitter;
                        const emberAlpha = alpha * (1 - i / 13) * 0.95;
                        ctx.fillStyle = i % 3 === 0 ? "rgba(255, 190, 229, " + emberAlpha + ")" : "rgba(176, 67, 255, " + emberAlpha + ")";
                        ctx.beginPath();
                        ctx.arc(emberX, emberY, 1.5 + random(seed + i * 13) * 3.5, 0, Math.PI * 2);
                        ctx.fill();
                    }

                    for (let i = 0; i < 7; i++) {
                        const offset = (random(seed + i * 17) - 0.5) * 22;
                        const flutter = Math.sin(sigils.phase * (45 + i * 2.7) + seed * 0.01 + i * 1.9);
                        drawFlameTongue(ctx, x + normalX * offset, y + normalY * offset,
                            tailAngle + (random(seed + i * 23) - 0.5) * 0.55 + flutter * 0.12,
                            38 + random(seed + i * 29) * 58, 11 + random(seed + i * 31) * 13,
                            alpha * (0.82 + random(seed + i * 37) * 0.18), i % 3 === 0);
                    }
                    drawFireballCore(ctx, x, y, 17 + Math.sin(sigils.phase * 24 + seed) * 1.2, alpha);
                }

                function drawDirectionalSweep(ctx, progress, alpha) {
                    const margin = 28;
                    const exponentialTravel = (Math.pow(2, progress * 4) - 1) / 15;
                    const travel = progress * 0.7 + exponentialTravel * 0.3;
                    let x1;
                    let y1;
                    let x2;
                    let y2;
                    let moveX = 0;
                    let moveY = 0;

                    if (sigils.direction === "right" || sigils.direction === "left") {
                        moveX = sigils.direction === "right" ? 1 : -1;
                        x1 = x2 = moveX > 0 ? -18 + travel * (width + 36) : width + 18 - travel * (width + 36);
                        y1 = margin;
                        y2 = height - margin;
                    } else {
                        moveY = sigils.direction === "down" ? 1 : -1;
                        y1 = y2 = moveY > 0 ? -18 + travel * (height + 36) : height + 18 - travel * (height + 36);
                        x1 = margin;
                        x2 = width - margin;
                    }

                    ctx.save();
                    ctx.globalCompositeOperation = "lighter";
                    drawEdgeFireball(ctx, x1, y1, moveX, moveY, alpha, 1100);
                    drawEdgeFireball(ctx, x2, y2, moveX, moveY, alpha, 1300);
                    ctx.restore();
                }

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const alpha = sigils.effectType === "direction" ? directionEnvelope(sigils.phase) : envelope(sigils.phase);
                    if (alpha < 0.01)
                        return;
                    if (sigils.effectType === "direction") {
                        drawDirectionalSweep(ctx, sigils.phase, alpha);
                        return;
                    }

                    const progress = easeOutCubic(sigils.phase);
                    const baseRadius = Math.min(width, height) * 0.145;
                    const radius = baseRadius * (0.62 + progress * 0.5);

                    ctx.save();
                    ctx.translate(width / 2, height / 2);
                    ctx.globalCompositeOperation = "lighter";

                    const aura = ctx.createRadialGradient(0, 0, radius * 0.5, 0, 0, radius * 1.35);
                    aura.addColorStop(0, "rgba(233, 30, 99, 0)");
                    aura.addColorStop(0.62, "rgba(233, 30, 99, " + (alpha * 0.035) + ")");
                    aura.addColorStop(0.82, "rgba(255, 86, 145, " + (alpha * 0.12) + ")");
                    aura.addColorStop(1, "rgba(190, 18, 77, 0)");
                    ctx.fillStyle = aura;
                    ctx.beginPath();
                    ctx.arc(0, 0, radius * 1.35, 0, Math.PI * 2);
                    ctx.fill();

                    drawBrokenRing(ctx, radius, alpha);
                    drawParticles(ctx, radius, alpha);
                    drawSparks(ctx, radius, alpha);
                    drawOrbitalFireball(ctx, radius, alpha);
                    drawAngularRose(ctx, radius * 0.42, alpha);

                    ctx.globalCompositeOperation = "source-over";
                    ctx.restore();
                }

                Connections {
                    target: sigils

                    function onPhaseChanged() {
                        canvas.requestPaint();
                    }
                }
            }

            NumberAnimation {
                running: true
                target: sigils
                property: "phase"
                from: 0
                to: 1
                duration: sigils.effectType === "direction" ? 320 : 430
                easing.type: Easing.Linear

                onFinished: {
                    sigils.visible = false;
                    if (root.sigilWindow === sigils)
                        root.sigilWindow = null;
                    sigils.destroy();
                }
            }
        }
    }
}
