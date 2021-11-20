import * as dotenv from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";

dotenv.config();

const privateKey =
  process.env.PRIVATE_KEY ||
  "0x0123456789012345678901234567890123456789012345678901234567890123";

const config: HardhatUserConfig = {
  solidity: "0.8.4",
  networks: {
    hardhat: {
      chainId: 1337,
    },
    local: {
      chainId: 1337,
      url: `http://127.0.0.1:8545`,
    },
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts: privateKey ? [privateKey] : [],
    },
  },
  defaultNetwork: "local",
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
