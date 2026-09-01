import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand(
            "audioMixer.checkPwMetadata",
            ["pw-metadata", "--help"],
            (stdout, exitCode) => {
                if (exitCode !== 0)
                    done("pw-metadata is required for per-application output routing")
                else
                    done(null)
            }
        )
    }
}
