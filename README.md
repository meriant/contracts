# Meriant Contracts

Meriant aggregates liquidity from decentralized exchanges on EVM networks. The Meriant API finds routes and builds
unsigned transactions. [SwapRouter](src/SwapRouter.sol) settles direct, multihop, and split routes in a single
transaction, enforcing the caller's amount limits and deadline. [Meriant app](https://meriant.xyz/)

## Mainnet deployments

All five networks use the same **SwapRouter** address, `0x00000006bb6441800E93377b5a2Df8D1a4CBC040`, and the same
**CREATE3 factory** address, `0xCaca7088ba73E5dF2830388E6E370884A097852a`. Each deployment record includes the chain's
executor addresses and the transaction hash for each deployment.

| Network  | Chain ID | SwapRouter                                                                                                   | Deployment record                          |
| -------- | -------: | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------ |
| Ethereum |        1 | [Etherscan](https://etherscan.io/address/0x00000006bb6441800E93377b5a2Df8D1a4CBC040)                         | [ethereum.json](deployments/ethereum.json) |
| Flare    |       14 | [Flare Explorer](https://flare-explorer.flare.network/address/0x00000006bb6441800E93377b5a2Df8D1a4CBC040)    | [flare.json](deployments/flare.json)       |
| Filecoin |      314 | [Filecoin Blockscout](https://filecoin.blockscout.com/address/0x00000006bb6441800E93377b5a2Df8D1a4CBC040)    | [filecoin.json](deployments/filecoin.json) |
| Metis    |     1088 | [Andromeda Explorer](https://andromeda-explorer.metis.io/address/0x00000006bb6441800E93377b5a2Df8D1a4CBC040) | [metis.json](deployments/metis.json)       |
| Ink      |    57073 | [Ink Explorer](https://explorer.inkonchain.com/address/0x00000006bb6441800E93377b5a2Df8D1a4CBC040)           | [ink.json](deployments/ink.json)           |

## Integrating with the router

Get a quote with `POST /v1/quote` and construct the unsigned transaction with `POST /v1/calldata`, or encode the route
directly using the [router interface](src/interfaces/ISwapRouter.sol) and [route structs](src/core/RouteTypes.sol).

| Swap         | Direct ERC-20 approval | Permit2                  | Settlement                                                                                          |
| ------------ | ---------------------- | ------------------------ | --------------------------------------------------------------------------------------------------- |
| Exact input  | `exactInput`           | `exactInputWithPermit2`  | Spend `amountIn` and deliver at least `amountOutMinimum` to the recipient.                          |
| Exact output | `exactOutput`          | `exactOutputWithPermit2` | Deliver at least `amountOut`, spend up to `amountInMaximum`, and refund unused input to the caller. |

- **Direct approval.** Approve the router to spend the input token.
- **Permit2.** Read `permit2()` on the target router and approve that contract to spend the input token. To grant the
  router an allowance in the same swap, pass the nonce and signature of a `PermitSingle` that names the router as
  spender. Sign for `amountIn` or `amountInMaximum`, with both expiration and signature deadline set to the swap
  `deadline`. Pass an empty signature to use a sufficient unexpired Permit2 allowance.
- **Native currency.** Use `address(0)` in the on-chain parameters. For native input, set `msg.value` to `amountIn` on
  an exact-input swap or `amountInMaximum` on an exact-output swap. For ERC-20 input, set `msg.value` to zero. A direct
  wrap or unwrap uses one step with a zero executor and empty step data.

Amounts are expressed in token base units, and `deadline` is a Unix timestamp in seconds. Each successful swap emits
`SwapExecuted` with the payer, recipient, tokens, and settled amounts.

## Contract architecture

- [SwapRouter](src/SwapRouter.sol) is the public entry point. It collects input, executes the supplied paths, settles
  output, and checks the final amounts using observed balance changes.
- [Executors](src/executors/) implement protocol-specific pool calls and callbacks. Each DEX step selects an enabled
  executor and supplies its protocol-specific data.
- [ExecutorRegistry](src/core/ExecutorRegistry.sol) controls which executors can run. The router is deployed without a
  proxy. Its owner can enable or disable executors, which run through `delegatecall` in the router's context. The
  executor allowlist is part of the router's trust model.

## Development

Install [Foundry](https://getfoundry.sh/) and [Bun](https://bun.sh/), then run from the repository root.

```bash
git submodule update --init --recursive
bun install --frozen-lockfile
forge build
forge test --offline
bun run lint
```

The [test suite](test/) covers router behavior, protocol executors, calldata integration, and gas usage. To run the
Flare fork suite, set `FLARE_RPC_URL` to a Flare mainnet RPC. Set `FLARE_FORK_BLOCK` to pin the fork to a specific
block.

```bash
RPC_URL="$FLARE_RPC_URL" forge test --match-contract FlareExecutorsForkTest
```

The opt-in Go calldata test documents its environment variables in [Calldata.t.sol](test/integration/Calldata.t.sol).

## Reproducing a deployment

Set the network and constructor inputs from [`.env.example`](.env.example) in a private local environment. Use the
`default` profile in [foundry.toml](foundry.toml) for deployment and source verification. It pins Solidity 0.8.37,
Shanghai, and 10,000 optimizer runs. The IR pipeline and compiler metadata bytecode hash are disabled.

1. Fund the deployment signer on the target chain. Deploy the [CREATE3 factory](script/DeployCreate3Factory.s.sol) at
   signer nonce zero. The script reads `DEPLOYER_PRIVATE_KEY` and checks the factory address and runtime bytecode.
2. Deploy the required [executor contracts](src/executors/) with their protocol-specific constructor arguments.
3. Run [DeploySwapRouter](script/DeploySwapRouter.s.sol) with the same signer through Foundry's `--account` flag. Set
   `ROUTER_SALT`, `ROUTER_OWNER`, `PERMIT_2`, `WRAPPED_NATIVE`, and comma-separated `EXECUTOR_ADDRESSES`. The script
   checks the predicted router address and its constructor configuration and executor registrations.

Run the scripts with `--rpc-url "$RPC_URL"` first to simulate the deployment. Add `--broadcast` after reviewing the
simulation. Reuse the same signer, nonce-zero factory deployment, and router salt on each network to reproduce the
addresses. Verify the source on the chain's explorer with the exact constructor arguments.

## Security

Report suspected vulnerabilities privately by email. [contact@meriant.xyz](mailto:contact@meriant.xyz)

## License

[MIT](LICENSE.md)
