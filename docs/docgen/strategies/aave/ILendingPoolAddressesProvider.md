# Solidity API

## ILendingPoolAddressesProvider

_Main registry of addresses part of or connected to the protocol, including permissioned roles
- Acting also as factory of proxies and admin of those, so with right to change its implementations
- Owned by the Aave Governance_

### MarketIdSet

```solidity
event MarketIdSet(string newMarketId)
```

### LendingPoolUpdated

```solidity
event LendingPoolUpdated(address newAddress)
```

### ConfigurationAdminUpdated

```solidity
event ConfigurationAdminUpdated(address newAddress)
```

### EmergencyAdminUpdated

```solidity
event EmergencyAdminUpdated(address newAddress)
```

### LendingPoolConfiguratorUpdated

```solidity
event LendingPoolConfiguratorUpdated(address newAddress)
```

### LendingPoolCollateralManagerUpdated

```solidity
event LendingPoolCollateralManagerUpdated(address newAddress)
```

### PriceOracleUpdated

```solidity
event PriceOracleUpdated(address newAddress)
```

### LendingRateOracleUpdated

```solidity
event LendingRateOracleUpdated(address newAddress)
```

### ProxyCreated

```solidity
event ProxyCreated(bytes32 id, address newAddress)
```

### AddressSet

```solidity
event AddressSet(bytes32 id, address newAddress, bool hasProxy)
```

### getMarketId

```solidity
function getMarketId() external view returns (string)
```

### setMarketId

```solidity
function setMarketId(string marketId) external
```

### setAddress

```solidity
function setAddress(bytes32 id, address newAddress) external
```

### setAddressAsProxy

```solidity
function setAddressAsProxy(bytes32 id, address impl) external
```

### getAddress

```solidity
function getAddress(bytes32 id) external view returns (address)
```

### getLendingPool

```solidity
function getLendingPool() external view returns (address)
```

### setLendingPoolImpl

```solidity
function setLendingPoolImpl(address pool) external
```

### getLendingPoolConfigurator

```solidity
function getLendingPoolConfigurator() external view returns (address)
```

### setLendingPoolConfiguratorImpl

```solidity
function setLendingPoolConfiguratorImpl(address configurator) external
```

### getLendingPoolCollateralManager

```solidity
function getLendingPoolCollateralManager() external view returns (address)
```

### setLendingPoolCollateralManager

```solidity
function setLendingPoolCollateralManager(address manager) external
```

### getPoolAdmin

```solidity
function getPoolAdmin() external view returns (address)
```

### setPoolAdmin

```solidity
function setPoolAdmin(address admin) external
```

### getEmergencyAdmin

```solidity
function getEmergencyAdmin() external view returns (address)
```

### setEmergencyAdmin

```solidity
function setEmergencyAdmin(address admin) external
```

### getPriceOracle

```solidity
function getPriceOracle() external view returns (address)
```

### setPriceOracle

```solidity
function setPriceOracle(address priceOracle) external
```

### getLendingRateOracle

```solidity
function getLendingRateOracle() external view returns (address)
```

### setLendingRateOracle

```solidity
function setLendingRateOracle(address lendingRateOracle) external
```

