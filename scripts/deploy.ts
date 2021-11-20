
import { ethers } from "hardhat";

async function main() {

  const Multisig = await ethers.getContractFactory("Multisig");
  // const multisig = await Multisig.deploy();

  // await multisig.deployed();

  // console.log("Multisig deployed to:", multisig.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
