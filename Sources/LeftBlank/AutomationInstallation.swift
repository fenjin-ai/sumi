import Foundation
import LeftBlankCore

enum AutomationInstallation {
    static func prompt(bundle: URL, distribution: String, serverName: String) -> String {
        let helper = bundle.appendingPathComponent("Contents/Helpers/LeftBlankMCP").path
        let launch = distribution == "appstore" ? """
        This is the Mac App Store edition. Install the standalone macOS arm64 MCP helper from the official
        https://github.com/leftblank-app/leftblank releases. Find the newest versioned release containing
        LeftBlankMCP-macOS-arm64.zip and its .sha256 asset; download both over HTTPS and verify the checksum.
        Extract only LeftBlankMCP into a private user-owned Application Support directory. Verify its code
        signature, TeamIdentifier and com.apple.security.application-groups entitlement against this installed
        LeftBlank app before executing it. The helper must be a member of the app's LeftBlankAgentGroup.
        Use the verified standalone executable with --app-bundle and the app path below.
        """ : """
        Use the app's bundled helper at \(helper), passing --app-bundle and the app path below.
        The helper is already compiled; no Rust, Swift, Node, Python or package installation is needed.
        """
        return """
        Configure LeftBlank MCP for the coding-agent client running this conversation on this Mac.
        App path: \(bundle.path)
        MCP server name: \(serverName)
        \(launch)
        Detect this client's supported MCP configuration mechanism, using its CLI help or official documentation.
        For Codex, use `codex mcp add \(serverName) -- <helper> --app-bundle <app-path>` with correct argument quoting.
        For another client, configure the equivalent local stdio command and arguments.
        Preserve all other client configuration. If this server already exists, update it instead of duplicating it.
        Open the app if necessary. Run the helper's --describe and --check with --app-bundle to verify installation
        and the live app bridge. Agent Access must be enabled in LeftBlank; only the user controls that switch.
        Reload MCP connections using the client's supported mechanism, then call leftblank_get_status to verify
        the actual MCP connection. A configuration entry alone is not proof of a working connection.
        If the client requires a new session, explain that precisely and finish the configuration first.
        Do the setup yourself; do not ask the user to run terminal commands or edit configuration files.
        """
    }
}
