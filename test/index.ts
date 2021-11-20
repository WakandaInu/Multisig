import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { FakeBUSD, MockToken, Multisig } from "../typechain";
// import { MockToken, Multisig } from "../typechain";
// import { FakeBUSD } from "../typechain/FakeBUSD";

describe("Multisig", function () {
  let signers: SignerWithAddress[];
  let multisig: Multisig;
  let mocktoken: MockToken;
  let fakeBUSDToken: FakeBUSD;
  let multisigSigners: string[];
  const reqApprovals = 1;

  async function transferContract() {
    const prevOwner = await mocktoken.owner(); // should be the deployer
    await mocktoken.transferOwnership(multisig.address); // execute on target contract first
    const newOwner = await mocktoken.owner(); // should be the multisig
    return { prevOwner, newOwner };
  }

  beforeEach(async () => {
    signers = await ethers.getSigners();
    multisigSigners = [signers[0].address, signers[1].address];
    const MockToken = await ethers.getContractFactory("MockToken");
    mocktoken = await MockToken.deploy();
    const Multisig = await ethers.getContractFactory("Multisig");
    multisig = await Multisig.deploy(multisigSigners, reqApprovals);

    const FakeBUSDToken = await ethers.getContractFactory("FakeBUSD");
    fakeBUSDToken = await FakeBUSDToken.deploy();
    await fakeBUSDToken.transfer(
      mocktoken.address,
      ethers.utils.parseUnits("10000", 6)
    );
  });

  it("should have correct numbers of signers", async () => {
    const owners = [];
    for (let i = 0; i < multisigSigners.length; i++) {
      const owner = await multisig.signers(i);
      owners.push(owner);
    }
    const reqSignatures = await multisig.numConfirmationsRequired();
    expect(Number(reqSignatures)).to.eq(1);
    expect(await multisig.signers(0)).to.eq(signers[0].address);
    expect(await multisig.signers(1)).to.eq(signers[1].address);
  });

  it("should transfer ownership of targetContract", async () => {
    const { prevOwner, newOwner } = await transferContract();

    await multisig.requestTransferOwnership(
      mocktoken.address,
      signers[1].address
    );

    await multisig.approveProposal(0);
    await multisig.executeRemoteProposal(0);

    const currentOwner = await mocktoken.owner(); // should be signer[1]

    expect(prevOwner).to.not.eq(newOwner);
    expect(newOwner).to.eq(multisig.address);
    expect(currentOwner).to.eq(signers[1].address);
  });

  it("should not create proposal by invalid signer", async () => {
    await transferContract();
    try {
      await multisig
        .connect(signers[2])
        .requestTransferOwnership(mocktoken.address, signers[1].address);
    } catch (e: any) {
      expect(e.message).includes("Not A Signer");
    }
  });

  it("should not execute proposal by invalid signer", async () => {
    await transferContract();
    await multisig.requestTransferOwnership(
      mocktoken.address,
      signers[1].address
    );

    try {
      await multisig.connect(signers[2]).approveProposal(0);
    } catch (e: any) {
      expect(e.message).includes("Not A Signer");
    }
  });

  it("should withdraw specific token from target and be able to send to a receiver", async () => {
    await transferContract();
    await multisig.requestTokenWithdrawalOnTarget(
      mocktoken.address,
      fakeBUSDToken.address
    );
    await multisig.approveProposal(0);
    await multisig.executeRemoteProposal(0);

    const amount = ethers.utils.parseUnits("10000", 6);

    await multisig.requestTokenTransfer(
      fakeBUSDToken.address,
      signers[3].address,
      amount
    );

    const prevBal = await fakeBUSDToken.balanceOf(signers[3].address);

    await multisig.approveProposal(1);
    await multisig.executeMultisigProposal(1);

    const newBal = await fakeBUSDToken.balanceOf(signers[3].address);

    expect(Number(prevBal)).to.eq(0);
    expect(Number(newBal)).to.eq(Number(amount));
  });

  it("should be able to reject a proposal", async () => {
    await transferContract();
    await multisig.requestTokenWithdrawalOnTarget(
      mocktoken.address,
      fakeBUSDToken.address
    );

    const proposalPrev = await multisig.getProposal(0);
    await multisig.connect(signers[1]).rejectProposal(0);
    const proposalNow = await multisig.getProposal(0);
    expect(proposalPrev.state).to.eq(0);
    expect(proposalNow.state).to.eq(2);
  });

  it("should throw error if approve -> reject instead of approve -> revoke -> reject", async () => {
    await transferContract();
    await multisig.requestTokenWithdrawalOnTarget(
      mocktoken.address,
      fakeBUSDToken.address
    );

    await multisig.connect(signers[1]).approveProposal(0);
    try {
      await multisig.connect(signers[1]).rejectProposal(0);
    } catch (e: any) {
      expect(e.message).includes("Revoke Approval First");
    }
  });

  it("should be able to withdraw donations and send it to a receiver", async () => {
    const amount = ethers.utils.parseEther("20");
    const prevBal = await ethers.provider.getBalance(signers[1].address);
    await signers[0].sendTransaction({
      value: amount,
      to: multisig.address,
    });

    const fundedBal = await ethers.provider.getBalance(multisig.address);

    await multisig.requestTransferETH(signers[1].address, amount);
    await multisig.approveProposal(0);
    await multisig.executeMultisigProposal(0);
    const emptyBal = await ethers.provider.getBalance(multisig.address);
    const newBal = await ethers.provider.getBalance(signers[1].address);

    expect(Number(newBal)).gt(Number(prevBal));
    expect(Number(emptyBal)).eq(Number(0));
    expect(Number(fundedBal)).eq(Number(amount));
  });

  it("should enable replacing of a signer", async () => {
    await multisig.requestReplaceSigner(
      signers[0].address,
      signers[3].address,
      0
    );

    const previously = await multisig.signers(0);

    await multisig.approveProposal(0);
    await multisig.executeMultisigProposal(0);

    const currently = await multisig.signers(0);

    expect(previously).to.eq(signers[0].address);
    expect(currently).to.eq(signers[3].address);
  });

  it("should not replace incorrect signer index", async () => {
    await mocktoken.transferOwnership(multisig.address);
    try {
      await multisig.requestReplaceSigner(
        signers[0].address,
        signers[3].address,
        0
      );
    } catch (e: any) {
      expect(e.message).to.include("Incorrect Signer Index");
    }
  });
});
