pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import "."

Item {
    id: root

    // PolkitAgent registers once, at construction, and polkit allows one agent per
    // session. Enabling ours while KDE's still holds the slot therefore failed for good:
    // nothing retried, so masking KDE's agent left the session with no agent at all.
    // Hosting it in a Loader lets a failed registration be thrown away and retried.
    property Component agentComp: Component {
        PolkitAgent {
            onAuthenticationRequestStarted: {
                root.errorMessage = "";
                root.requestStarted();
            }
        }
    }
    Loader {
        id: agentLoader
        active: true
        sourceComponent: root.agentComp
    }
    readonly property var agent: agentLoader.item

    readonly property bool isActive: root.agent ? root.agent.isActive : false
    readonly property bool isRegistered: root.agent ? root.agent.isRegistered : false
    readonly property var flow: root.agent ? root.agent.flow : null
    property string errorMessage: ""

    // Called when KDE's agent is masked, which is the only moment the slot frees.
    // Never mid-prompt: tearing the agent down would cancel the dialog under the user.
    function reregister() {
        if (root.isActive)
            return;
        agentLoader.active = false;
        agentLoader.active = true;
    }

    signal requestStarted()
    signal requestCancelled()
    signal authenticationFailed()
    signal authenticationSucceeded()

    function submit(response) {
        if (root.flow && typeof root.flow.submit === "function")
            root.flow.submit(response);
    }

    function cancel() {
        if (root.flow && typeof root.flow.cancelAuthenticationRequest === "function")
            root.flow.cancelAuthenticationRequest();
        root.errorMessage = "";
    }

    Connections {
        target: root.flow

        function onAuthenticationFailed() {
            if (root.flow && root.flow.supplementaryMessage)
                root.errorMessage = root.flow.supplementaryMessage;
            else
                root.errorMessage = typeof I18n !== "undefined" ? I18n.t("polkit.error_failed") : "Authentication failed. Please try again.";
            root.authenticationFailed();
        }

        function onAuthenticationSucceeded() {
            root.errorMessage = "";
            root.authenticationSucceeded();
        }

        function onAuthenticationRequestCancelled() {
            root.errorMessage = "";
            root.requestCancelled();
        }

        function onSupplementaryMessageChanged() {
            if (root.flow && root.flow.supplementaryIsError && root.flow.supplementaryMessage)
                root.errorMessage = root.flow.supplementaryMessage;
        }
    }
}
