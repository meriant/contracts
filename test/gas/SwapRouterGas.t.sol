// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { RouterFixture } from "../fixtures/RouterFixture.sol";

/// @notice Measures the router call only, with identical mock tokens and a 100-in/200-out trade.
/// @dev These snapshots compare route shapes; they are not estimates for a live DEX transaction.
contract SwapRouterGasTest is RouterFixture {
    function setUp() public override {
        super.setUp();
        vm.prank(USER);
        tokenA.approve(address(router), 1000);
    }

    function testGasExactInputDirect() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInput(_inputParams(address(tokenA), address(tokenC), 100, 200, paths));
        emit log_named_uint("exactInput/direct/allowance", gasBefore - gasleft());
    }

    function testGasExactInputMultihop() public {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = _inputStep(address(executorA), address(tokenB), 1, 1);
        steps[1] = _inputStep(address(executorB), address(tokenC), 2, 1);
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 100, steps: steps });

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInput(_inputParams(address(tokenA), address(tokenC), 100, 200, paths));
        emit log_named_uint("exactInput/multihop/allowance", gasBefore - gasleft());
    }

    function testGasExactInputSplit() public {
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](2);
        paths[0] = _exactInputPath(40, _inputStep(address(executorA), address(tokenC), 2, 1));
        paths[1] = _exactInputPath(60, _inputStep(address(executorB), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInput(_inputParams(address(tokenA), address(tokenC), 100, 200, paths));
        emit log_named_uint("exactInput/split/allowance", gasBefore - gasleft());
    }

    function testGasExactOutputDirect() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 200, 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactOutput(_outputParams(address(tokenA), address(tokenC), 200, 110, paths));
        emit log_named_uint("exactOutput/direct/allowance", gasBefore - gasleft());
    }

    function testGasExactOutputMultihop() public {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] = _outputStep(address(executorA), address(tokenB), 100, 1, 1);
        steps[1] = _outputStep(address(executorB), address(tokenC), 200, 2, 1);
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactOutput(_outputParams(address(tokenA), address(tokenC), 200, 110, paths));
        emit log_named_uint("exactOutput/multihop/allowance", gasBefore - gasleft());
    }

    function testGasExactOutputSplit() public {
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](2);
        paths[0] = _exactOutputPath(_outputStep(address(executorA), address(tokenC), 80, 2, 1));
        paths[1] = _exactOutputPath(_outputStep(address(executorB), address(tokenC), 120, 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactOutput(_outputParams(address(tokenA), address(tokenC), 200, 110, paths));
        emit log_named_uint("exactOutput/split/allowance", gasBefore - gasleft());
    }

    function testGasExactInputDirectPermit2() public {
        RouteTypes.ExactInputPath[] memory paths =
            _singleExactInputPath(100, _inputStep(address(executorA), address(tokenC), 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInputWithPermit2(_inputParams(address(tokenA), address(tokenC), 100, 200, paths), _permit());
        emit log_named_uint("exactInput/direct/permit2", gasBefore - gasleft());
    }

    function testGasExactOutputDirectPermit2() public {
        RouteTypes.ExactOutputPath[] memory paths =
            _singleExactOutputPath(_outputStep(address(executorA), address(tokenC), 200, 2, 1));

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactOutputWithPermit2(_outputParams(address(tokenA), address(tokenC), 200, 110, paths), _permit());
        emit log_named_uint("exactOutput/direct/permit2", gasBefore - gasleft());
    }

    function testGasWrapNative() public {
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({ executor: address(0), tokenOut: address(wrappedNative), data: "" });
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 100, steps: steps });

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInput{ value: 100 }(_inputParams(address(0), address(wrappedNative), 100, 100, paths));
        emit log_named_uint("exactInput/native-wrap", gasBefore - gasleft());
    }

    function testGasUnwrapNative() public {
        wrappedNative.mint(USER, 100);
        vm.prank(USER);
        wrappedNative.approve(address(permit2), 100);
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({ executor: address(0), tokenOut: address(0), data: "" });
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 100, steps: steps });

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        router.exactInputWithPermit2(_inputParams(address(wrappedNative), address(0), 100, 100, paths), _permit());
        emit log_named_uint("exactInput/native-unwrap/permit2", gasBefore - gasleft());
    }
}
