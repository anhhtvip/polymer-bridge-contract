# L2 Eth Bridge
- Frontend: https://github.com/anhhtvip/eth-bridge-polymer-chain
- Live demo: https://bridge.tuananh.xyz
- Video demo: https://www.youtube.com/watch?v=ZHLzDZLNSLM

# How to deploy the bridge
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
just deposit
just bridge
```
