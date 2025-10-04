-include .env
export
# Variables
RPC_URL := $(SEPOLIA_URL)
PRIVATE_KEY := $(SEPOLIA_PK)
ETHERSCAN_API_KEY := $(ETHERSCAN_API_KEY)

test:
	@forge test

deploy-sepolia:
	forge script script/DeployDSC.s.sol:DeployDSC \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) 


verify-sepolia:
	forge verify-contract \
		--rpc-url $(RPC_URL) \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		0xF67FE18fCfe6fEb50c0dc8D52C7990D38395dc20 \
		src/DSCEngine.sol:DSCEngine

print-env:
	@echo RPC_URL=$(RPC_URL)