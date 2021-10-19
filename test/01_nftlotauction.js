const { expect } = require('chai');
const { deployments, ethers } = require('hardhat');

describe('NFTLotAuction', () => {
    let deployer;
    let random;
    let minter;

    let factory;
    let series;

    beforeEach(async () => {
        [deployer, random, minter] = await ethers.getSigners();

        await deployments.fixture();
        NFTLotAuction = await deployments.get('NFTLotAuction');
        auction = await ethers.getContractAt(
            'NFTLotAuction',
            NFTLotAuction.address,
            deployer,
        );
    });

    describe('Create Auction', async function () {});
});
