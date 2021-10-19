// deploy/00_deploy_my_contract.js
module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy } = deployments;
    const { deployer, signer } = await getNamedAccounts();

    await deploy('NFTLotAuction', {
        from: deployer,
        log: true,
    });
};
module.exports.tags = ['NFTLotAuction'];
