export function parseError(error) {
  if (!error) return 'Unknown error occurred'

  const errorMessage = error.message || error.toString()
  
  if (errorMessage.includes('execution reverted')) {
    if (errorMessage.includes('AccessControl')) {
      return 'Access denied: You do not have the required role for this action'
    }
    if (errorMessage.includes('REWARD_MANAGER_ROLE')) {
      return 'Access denied: You need REWARD_MANAGER_ROLE to distribute rewards'
    }
    if (errorMessage.includes('InsufficientRewardPool')) {
      return 'Insufficient reward pool balance'
    }
    if (errorMessage.includes('InsufficientBalance') || errorMessage.includes('ERC20InsufficientBalance')) {
      return 'Insufficient token balance'
    }
    if (errorMessage.includes('Pausable: paused')) {
      return 'Contract is currently paused'
    }
    if (errorMessage.includes('ZeroAddress')) {
      return 'Invalid address: Cannot use zero address'
    }
    if (errorMessage.includes('ZeroAmount')) {
      return 'Invalid amount: Amount must be greater than zero'
    }
    if (errorMessage.includes('TransferAmountTooLow')) {
      return 'Transfer amount too low: Tax would consume entire amount'
    }
    return 'Transaction reverted: Check your permissions and balance'
  }

  if (errorMessage.includes('user rejected')) {
    return 'Transaction rejected by user'
  }

  if (errorMessage.includes('insufficient funds')) {
    return 'Insufficient ETH balance for gas fees'
  }

  if (error.reason) {
    return error.reason
  }

  return errorMessage
}

export async function checkRole(contract, account, roleHash) {
  if (!contract || !account) return false
  try {
    return await contract.hasRole(roleHash, account)
  } catch {
    return false
  }
}

export async function checkBalance(contract, account) {
  if (!contract || !account) return '0'
  try {
    const balance = await contract.balanceOf(account)
    return balance.toString()
  } catch {
    return '0'
  }
}

export async function checkPaused(contract) {
  if (!contract) return false
  try {
    return await contract.paused()
  } catch {
    return false
  }
}

