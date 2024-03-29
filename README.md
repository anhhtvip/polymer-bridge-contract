## Run All Task

```bash
just do-bridge
```

## Steps

### Set Bridge Contract

```bash
just set-contracts optimism Bridge false && just set-contracts base Bridge false
```

### Deploy Contracts

```bash
just deploy optimism base
```

### Sanity check to verify that configuration files match with your deployed contracts

```bash
just sanity-check
```

### Create Channel

```bash
just create-channel
```

### Send package

```bash
npx hardhat run scripts/XBridge/deposit.js --network base
npx hardhat run scripts/XBridge/bridge.js --network optimism
```
