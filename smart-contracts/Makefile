-include .env # Create Local Variables and rename 
export

RPC_URL := $(ENV_RPC_URL)

build:
	@forge build

test:
	@forge test

clean:
	@forge clean


simulate-deploy:
	forge script script/DeployAZD.s.sol:DeployAZD \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--dry-run


deploy-verify-sepolia:
	forge script script/DeployAZD.s.sol:DeployAZD \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) 

print-env:
	@echo RPC_URL=$(RPC_URL)