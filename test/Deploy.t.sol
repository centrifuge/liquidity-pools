import {ConnectorXCMScript} from "../script/Connector-XCM.s.sol";

import "forge-std/Test.sol";

contract DeployTest is Test {

    function testXCMDeployWorks() public {
        ConnectorXCMScript script = new ConnectorXCMScript();
        script.run();
    }

}