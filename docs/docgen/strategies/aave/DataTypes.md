# Solidity API

## DataTypes

### ReserveData

```solidity
struct ReserveData {
  struct DataTypes.ReserveConfigurationMap configuration;
  uint128 liquidityIndex;
  uint128 variableBorrowIndex;
  uint128 currentLiquidityRate;
  uint128 currentVariableBorrowRate;
  uint128 currentStableBorrowRate;
  uint40 lastUpdateTimestamp;
  address aTokenAddress;
  address stableDebtTokenAddress;
  address variableDebtTokenAddress;
  address interestRateStrategyAddress;
  uint8 id;
}
```

### ReserveConfigurationMap

```solidity
struct ReserveConfigurationMap {
  uint256 data;
}
```

### UserConfigurationMap

```solidity
struct UserConfigurationMap {
  uint256 data;
}
```

### InterestRateMode

```solidity
enum InterestRateMode {
  NONE,
  STABLE,
  VARIABLE
}
```

