// SPDX-License-Identifier: MIT
pragma solidity >=0.8.37 <0.9.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/src/Test.sol";

import { SwapRouter } from "../../src/SwapRouter.sol";
import { RouteTypes } from "../../src/core/RouteTypes.sol";
import { AlgebraExecutor } from "../../src/executors/AlgebraExecutor.sol";
import { EnosysV3Executor } from "../../src/executors/EnosysV3Executor.sol";
import { UniswapV2Executor } from "../../src/executors/UniswapV2Executor.sol";
import { UniswapV3Executor } from "../../src/executors/UniswapV3Executor.sol";
import { ISwapRouter } from "../../src/interfaces/ISwapRouter.sol";
import { IPermit2 } from "../../src/interfaces/IPermit2.sol";

contract FlareExecutorsForkTest is Test {
    address private constant USER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);

    address private constant WFLR = 0x1D80c49BbBCd1C0911346656B529DF9E5c2F783d;
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant USDT0 = 0xe7cd86e13AC4309349F30B3435a9d337750fC82D;
    address private constant USDC_E = 0xFbDa5F676cB37624f28265A144A48B0d6e87d3b6;
    address private constant FXRP = 0xAd552A648C74D49E10027AB8a618A3ad4901c5bE;
    address private constant FCAT = 0xbF6d832350c5FB787d3822841dC930C5ebdbb888;
    address private constant HLN = 0x140D8d3649Ec605CF69018C627fB44cCC76eC89f;

    address private constant SPARKDEX_V3_FACTORY = 0x8A2578d23d4C532cC9A98FaD91C0523f5efDE652;
    address private constant ENOSYS_V3_FACTORY = 0x17AA157AC8C54034381b840Cb8f6bf7Fc355f0de;
    address private constant SPARKDEX_V4_FACTORY = 0x805488DaA81c1b9e7C5cE3f1DCeA28F21448EC6A;
    address private constant BLAZESWAP_FACTORY = 0x440602f459D7Dd500a74528003e6A20A46d6e2A6;

    address private constant SPARKDEX_V3_POOL = 0x0B40111B4Cf6dD1001F36f9c631956FefA56BC3b;
    address private constant ENOSYS_V3_POOL = 0xA7C9E7343bD8f1eb7000F25dE5aeb52c6B78B1b7;
    address private constant SPARKDEX_V4_POOL = 0xdCEA6d3d7Ca3b67c02D2b242A9037f8aFE613C27;
    address private constant SPARKDEX_V4_CUSTOM_POOL = 0xAFaC77447004De0ca8b8bD733C319A5fe7f08B40;
    address private constant BLAZESWAP_PAIR = 0x5eD30e42757E3edd2f898FbcA26Cd7c6f391Ae1C;
    address private constant SPARKDEX_V4_CUSTOM_DEPLOYER = 0x89C5CA927aA9f91f4CF672C0e2D2cc69bE4B8A77;
    address private constant FXRP_FUNDER = 0x927485d88a66253c63Af9163dca5f21c25A57393;

    uint24 private constant SPARKDEX_V3_FEE = 100;
    uint24 private constant ENOSYS_V3_FEE = 3000;

    bool private forkEnabled;
    SwapRouter private router;
    UniswapV3Executor private sparkDexV3Executor;
    EnosysV3Executor private enosysV3Executor;
    AlgebraExecutor private sparkDexV4Executor;
    UniswapV2Executor private blazeSwapV2Executor;

    modifier onlyFork() {
        if (!forkEnabled) vm.skip(true, "RPC_URL is not set");
        _;
    }

    function setUp() public {
        string memory rpcUrl = vm.envOr("RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;

        uint256 forkBlock = vm.envOr("FLARE_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }
        forkEnabled = true;

        sparkDexV3Executor = new UniswapV3Executor(SPARKDEX_V3_FACTORY);
        enosysV3Executor = new EnosysV3Executor(ENOSYS_V3_FACTORY);
        sparkDexV4Executor = new AlgebraExecutor(SPARKDEX_V4_FACTORY);
        blazeSwapV2Executor = new UniswapV2Executor(BLAZESWAP_FACTORY, 3000);

        address[] memory executors = new address[](4);
        executors[0] = address(sparkDexV3Executor);
        executors[1] = address(enosysV3Executor);
        executors[2] = address(sparkDexV4Executor);
        executors[3] = address(blazeSwapV2Executor);
        router = new SwapRouter(address(this), WFLR, PERMIT2, executors);

        deal(USDT0, USER, 100e6);
        deal(USDC_E, USER, 100e6);
        vm.prank(USER);
        IERC20(USDT0).approve(PERMIT2, type(uint256).max);
        vm.prank(USER);
        IPermit2(PERMIT2).approve(USDT0, address(router), type(uint160).max, type(uint48).max);
        vm.prank(USER);
        IERC20(USDC_E).approve(PERMIT2, type(uint256).max);
        vm.prank(USER);
        IPermit2(PERMIT2).approve(USDC_E, address(router), type(uint160).max, type(uint48).max);
    }

    function testForkSparkDEXV3ExactInput() public onlyFork {
        _testExactInput(
            address(sparkDexV3Executor), USDT0, USDC_E, 1e6, abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        );
    }

    function testForkBlazeSwapExactInput() public onlyFork {
        _testExactInput(address(blazeSwapV2Executor), USDT0, WFLR, 1e6, abi.encode(BLAZESWAP_PAIR));
    }

    function testForkBlazeSwapExactOutput() public onlyFork {
        _testExactOutput(address(blazeSwapV2Executor), USDT0, WFLR, 1e18, 2e6, abi.encode(BLAZESWAP_PAIR));
    }

    function testForkSparkDEXV3ExactOutput() public onlyFork {
        _testExactOutput(
            address(sparkDexV3Executor),
            USDT0,
            USDC_E,
            500_000,
            2e6,
            abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        );
    }

    function testForkEnosysV3ExactInput() public onlyFork {
        _testExactInput(
            address(enosysV3Executor), USDT0, HLN, 1e6, abi.encode(ENOSYS_V3_POOL, ENOSYS_V3_FEE, uint160(0))
        );
    }

    function testForkEnosysV3ExactOutput() public onlyFork {
        _testExactOutput(
            address(enosysV3Executor), USDT0, HLN, 1e18, 1e6, abi.encode(ENOSYS_V3_POOL, ENOSYS_V3_FEE, uint160(0))
        );
    }

    function testForkSparkDEXV4RegularPoolExactInput() public onlyFork {
        _testExactInput(
            address(sparkDexV4Executor), USDT0, USDC_E, 1e6, abi.encode(SPARKDEX_V4_POOL, address(0), uint160(0))
        );
    }

    function testForkSparkDEXV4RegularPoolExactOutput() public onlyFork {
        _testExactOutput(
            address(sparkDexV4Executor),
            USDT0,
            USDC_E,
            500_000,
            2e6,
            abi.encode(SPARKDEX_V4_POOL, address(0), uint160(0))
        );
    }

    function testForkSparkDEXV4CustomPoolExactInput() public onlyFork {
        _fundCustomPoolInput();
        _testExactInput(
            address(sparkDexV4Executor),
            FXRP,
            FCAT,
            1e6,
            abi.encode(SPARKDEX_V4_CUSTOM_POOL, SPARKDEX_V4_CUSTOM_DEPLOYER, uint160(0))
        );
    }

    function testForkSparkDEXV4CustomPoolExactOutput() public onlyFork {
        _fundCustomPoolInput();
        _testExactOutput(
            address(sparkDexV4Executor),
            FXRP,
            FCAT,
            1e18,
            10e6,
            abi.encode(SPARKDEX_V4_CUSTOM_POOL, SPARKDEX_V4_CUSTOM_DEPLOYER, uint160(0))
        );
    }

    function testForkMixedProtocolMultihopExactInput() public onlyFork {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](2);
        steps[0] = RouteTypes.ExactInputStep({
            executor: address(sparkDexV3Executor),
            tokenOut: USDT0,
            data: abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        });
        steps[1] = RouteTypes.ExactInputStep({
            executor: address(enosysV3Executor),
            tokenOut: HLN,
            data: abi.encode(ENOSYS_V3_POOL, ENOSYS_V3_FEE, uint160(0))
        });
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: 1e6, steps: steps });

        uint256 outputBefore = IERC20(HLN).balanceOf(RECIPIENT);
        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: USDC_E,
                tokenOut: HLN,
                amountIn: 1e6,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertGt(amountOut, 0);
        assertEq(IERC20(HLN).balanceOf(RECIPIENT) - outputBefore, amountOut);
    }

    function testForkMixedProtocolMultihopExactOutput() public onlyFork {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](2);
        steps[0] = RouteTypes.ExactOutputStep({
            executor: address(sparkDexV3Executor),
            tokenOut: USDT0,
            amountOut: 1e6,
            data: abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        });
        steps[1] = RouteTypes.ExactOutputStep({
            executor: address(enosysV3Executor),
            tokenOut: HLN,
            amountOut: 1e18,
            data: abi.encode(ENOSYS_V3_POOL, ENOSYS_V3_FEE, uint160(0))
        });
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });

        uint256 inputBefore = IERC20(USDC_E).balanceOf(USER);
        uint256 outputBefore = IERC20(HLN).balanceOf(RECIPIENT);
        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: USDC_E,
                tokenOut: HLN,
                amountOut: 1e18,
                amountInMaximum: 2e6,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertLe(amountIn, 2e6);
        assertEq(inputBefore - IERC20(USDC_E).balanceOf(USER), amountIn);
        assertEq(IERC20(HLN).balanceOf(RECIPIENT) - outputBefore, 1e18);
    }

    function testForkSplitExactInput() public onlyFork {
        RouteTypes.ExactInputPath[] memory paths = new RouteTypes.ExactInputPath[](2);
        paths[0] = _exactInputPath(
            address(sparkDexV3Executor),
            USDT0,
            USDC_E,
            500_000,
            abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        );
        paths[1] = _exactInputPath(
            address(sparkDexV4Executor), USDT0, USDC_E, 500_000, abi.encode(SPARKDEX_V4_POOL, address(0), uint160(0))
        );

        uint256 outputBefore = IERC20(USDC_E).balanceOf(RECIPIENT);
        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: USDT0,
                tokenOut: USDC_E,
                amountIn: 1e6,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertGt(amountOut, 0);
        assertEq(IERC20(USDC_E).balanceOf(RECIPIENT) - outputBefore, amountOut);
    }

    function testForkSplitExactOutput() public onlyFork {
        RouteTypes.ExactOutputPath[] memory paths = new RouteTypes.ExactOutputPath[](2);
        paths[0] = _exactOutputPath(
            address(sparkDexV3Executor),
            USDT0,
            USDC_E,
            500_000,
            abi.encode(SPARKDEX_V3_POOL, SPARKDEX_V3_FEE, uint160(0))
        );
        paths[1] = _exactOutputPath(
            address(sparkDexV4Executor), USDT0, USDC_E, 500_000, abi.encode(SPARKDEX_V4_POOL, address(0), uint160(0))
        );

        uint256 inputBefore = IERC20(USDT0).balanceOf(USER);
        uint256 outputBefore = IERC20(USDC_E).balanceOf(RECIPIENT);
        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: USDT0,
                tokenOut: USDC_E,
                amountOut: 1e6,
                amountInMaximum: 2e6,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: paths
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertLe(amountIn, 2e6);
        assertEq(inputBefore - IERC20(USDT0).balanceOf(USER), amountIn);
        assertEq(IERC20(USDC_E).balanceOf(RECIPIENT) - outputBefore, 1e6);
    }

    function _fundCustomPoolInput() private {
        vm.prank(FXRP_FUNDER);
        assertTrue(IERC20(FXRP).transfer(USER, 100e6));
        vm.prank(USER);
        IERC20(FXRP).approve(PERMIT2, type(uint256).max);
        vm.prank(USER);
        IPermit2(PERMIT2).approve(FXRP, address(router), type(uint160).max, type(uint48).max);
    }

    function _testExactInput(
        address executor,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes memory data
    )
        private
    {
        uint256 recipientBalanceBefore = IERC20(tokenOut).balanceOf(RECIPIENT);

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountOut = router.exactInputWithPermit2(
            RouteTypes.ExactInputParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                amountOutMinimum: 1,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactInputPaths(executor, tokenIn, tokenOut, amountIn, data)
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertGt(amountOut, 0);
        assertEq(IERC20(tokenOut).balanceOf(RECIPIENT) - recipientBalanceBefore, amountOut);
    }

    function _testExactOutput(
        address executor,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        bytes memory data
    )
        private
    {
        uint256 inputBalanceBefore = IERC20(tokenIn).balanceOf(USER);
        uint256 recipientBalanceBefore = IERC20(tokenOut).balanceOf(RECIPIENT);

        vm.prank(USER);
        uint256 gasBefore = gasleft();
        uint256 amountIn = router.exactOutputWithPermit2(
            RouteTypes.ExactOutputParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                recipient: RECIPIENT,
                deadline: block.timestamp,
                paths: _exactOutputPaths(executor, tokenIn, tokenOut, amountOut, data)
            }),
            _emptyPermit()
        );
        emit log_named_uint("SwapRouter gas", gasBefore - gasleft());

        assertGt(amountIn, 0);
        assertLe(amountIn, amountInMaximum);
        assertEq(inputBalanceBefore - IERC20(tokenIn).balanceOf(USER), amountIn);
        assertEq(IERC20(tokenOut).balanceOf(RECIPIENT) - recipientBalanceBefore, amountOut);
    }

    function _exactInputPaths(
        address executor,
        address,
        address tokenOut,
        uint256 amountIn,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactInputPath[] memory paths)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({ executor: executor, tokenOut: tokenOut, data: data });

        paths = new RouteTypes.ExactInputPath[](1);
        paths[0] = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _exactInputPath(
        address executor,
        address,
        address tokenOut,
        uint256 amountIn,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactInputPath memory path)
    {
        RouteTypes.ExactInputStep[] memory steps = new RouteTypes.ExactInputStep[](1);
        steps[0] = RouteTypes.ExactInputStep({ executor: executor, tokenOut: tokenOut, data: data });
        path = RouteTypes.ExactInputPath({ amountIn: amountIn, steps: steps });
    }

    function _emptyPermit() private pure returns (ISwapRouter.Permit2Permit memory) {
        return ISwapRouter.Permit2Permit({ nonce: 0, signature: "" });
    }

    function _exactOutputPaths(
        address executor,
        address,
        address tokenOut,
        uint256 amountOut,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactOutputPath[] memory paths)
    {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] =
            RouteTypes.ExactOutputStep({ executor: executor, tokenOut: tokenOut, amountOut: amountOut, data: data });

        paths = new RouteTypes.ExactOutputPath[](1);
        paths[0] = RouteTypes.ExactOutputPath({ steps: steps });
    }

    function _exactOutputPath(
        address executor,
        address,
        address tokenOut,
        uint256 amountOut,
        bytes memory data
    )
        private
        pure
        returns (RouteTypes.ExactOutputPath memory path)
    {
        RouteTypes.ExactOutputStep[] memory steps = new RouteTypes.ExactOutputStep[](1);
        steps[0] =
            RouteTypes.ExactOutputStep({ executor: executor, tokenOut: tokenOut, amountOut: amountOut, data: data });
        path = RouteTypes.ExactOutputPath({ steps: steps });
    }
}
