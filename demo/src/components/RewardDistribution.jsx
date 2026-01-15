import { useState, useEffect } from 'react'
import { parseTokenAmount, formatTokenAmount, shortenAddress, ROLES } from '../utils/contracts'
import { parseError, checkRole, checkPaused } from '../utils/errorHandler'
import './RewardDistribution.css'

function RewardDistribution({ web3 }) {
  const [recipient, setRecipient] = useState('')
  const [amount, setAmount] = useState('')
  const [batchMode, setBatchMode] = useState(false)
  const [batchRecipients, setBatchRecipients] = useState([{ address: '', amount: '' }])
  const [recentRewards, setRecentRewards] = useState([])
  const [rewardPool, setRewardPool] = useState('0')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  const [success, setSuccess] = useState(null)
  const [hasRewardRole, setHasRewardRole] = useState(false)
  const [isPaused, setIsPaused] = useState(false)

  useEffect(() => {
    if (web3.contract && web3.account) {
      loadRewardPool()
      checkPermissions()
      const interval = setInterval(() => {
        loadRewardPool()
        checkPermissions()
      }, 5000)
      return () => clearInterval(interval)
    }
  }, [web3.contract, web3.account])

  const checkPermissions = async () => {
    if (!web3.contract || !web3.account) return
    try {
      const [hasRole, paused] = await Promise.all([
        checkRole(web3.contract, web3.account, ROLES.REWARD_MANAGER_ROLE),
        checkPaused(web3.contract)
      ])
      setHasRewardRole(hasRole)
      setIsPaused(paused)
    } catch (err) {
      console.error('Error checking permissions:', err)
    }
  }

  const loadRewardPool = async () => {
    if (!web3.contract) return
    try {
      const pool = await web3.contract.rewardPoolBalance()
      setRewardPool(formatTokenAmount(pool))
    } catch (err) {
      console.error('Error loading reward pool:', err)
    }
  }

  const handleSingleReward = async (e) => {
    e.preventDefault()
    if (!web3.contract || !web3.isConnected) {
      setError('Please connect your wallet')
      return
    }

    if (!hasRewardRole) {
      setError('Access denied: You need REWARD_MANAGER_ROLE to distribute rewards. Only the treasury multi-sig has this role.')
      return
    }

    if (isPaused) {
      setError('Contract is currently paused. Please contact the admin to unpause.')
      return
    }

    if (!recipient || !amount) {
      setError('Please fill in all fields')
      return
    }

    setLoading(true)
    setError(null)
    setSuccess(null)

    try {
      const amountWei = parseTokenAmount(amount)
      const poolBalance = await web3.contract.rewardPoolBalance()
      if (amountWei > poolBalance) {
        setError(`Insufficient reward pool. Available: ${formatTokenAmount(poolBalance)} ACTX`)
        setLoading(false)
        return
      }

      const tx = await web3.contract.distributeReward(recipient, amountWei)
      setSuccess(`Transaction submitted: ${shortenAddress(tx.hash)}`)
      
      const receipt = await tx.wait()
      const reward = {
        recipient: shortenAddress(recipient),
        amount: amount,
        timestamp: new Date().toLocaleTimeString(),
        txHash: receipt.hash
      }
      setRecentRewards([reward, ...recentRewards].slice(0, 10))
      
      setRecipient('')
      setAmount('')
      await loadRewardPool()
    } catch (err) {
      setError(parseError(err))
      console.error('Error distributing reward:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleBatchReward = async (e) => {
    e.preventDefault()
    if (!web3.contract || !web3.isConnected) {
      setError('Please connect your wallet')
      return
    }

    const validRecipients = batchRecipients.filter(r => r.address && r.amount)
    if (validRecipients.length === 0) {
      setError('Please add at least one recipient')
      return
    }

    setLoading(true)
    setError(null)
    setSuccess(null)

    try {
      const addresses = validRecipients.map(r => r.address)
      const amounts = validRecipients.map(r => parseTokenAmount(r.amount))
      
      const tx = await web3.contract.batchDistributeRewards(addresses, amounts)
      setSuccess(`Batch transaction submitted: ${shortenAddress(tx.hash)}`)
      
      const receipt = await tx.wait()
      validRecipients.forEach(r => {
        const reward = {
          recipient: shortenAddress(r.address),
          amount: r.amount,
          timestamp: new Date().toLocaleTimeString(),
          txHash: receipt.hash
        }
        setRecentRewards(prev => [reward, ...prev].slice(0, 10))
      })
      
      setBatchRecipients([{ address: '', amount: '' }])
      await loadRewardPool()
    } catch (err) {
      setError(parseError(err))
      console.error('Error distributing batch rewards:', err)
    } finally {
      setLoading(false)
    }
  }

  const addBatchRecipient = () => {
    setBatchRecipients([...batchRecipients, { address: '', amount: '' }])
  }

  const updateBatchRecipient = (index, field, value) => {
    const updated = [...batchRecipients]
    updated[index][field] = value
    setBatchRecipients(updated)
  }

  if (!web3.isConnected) {
    return (
      <div className="reward-distribution">
        <div className="connect-prompt">
          <h2>CONNECT WALLET</h2>
          <p>Connect your wallet to distribute rewards</p>
          <button className="connect-btn-large" onClick={web3.connectWallet}>
            CONNECT WALLET
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="reward-distribution">
      <div className="section-header">
        <h2>REWARD DISTRIBUTION</h2>
        <p>Distribute tokens from reward pool to eligible recipients</p>
      </div>

      {!hasRewardRole && web3.isConnected && (
        <div className="alert warning">
          ⚠️ You do not have REWARD_MANAGER_ROLE. Only addresses with this role can distribute rewards. 
          The treasury multi-sig (0x7E14...E41a) has this role.
        </div>
      )}

      {isPaused && (
        <div className="alert error">
          ⚠️ Contract is currently paused. Rewards cannot be distributed.
        </div>
      )}

      {error && <div className="alert error">{error}</div>}
      {success && <div className="alert success">{success}</div>}

      <div className="mode-toggle">
        <button
          className={!batchMode ? 'active' : ''}
          onClick={() => setBatchMode(false)}
        >
          Single Distribution
        </button>
        <button
          className={batchMode ? 'active' : ''}
          onClick={() => setBatchMode(true)}
        >
          Batch Distribution
        </button>
      </div>

      {!batchMode ? (
        <form className="reward-form" onSubmit={handleSingleReward}>
          <div className="form-group">
            <label>Recipient Address</label>
            <input
              type="text"
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="0x..."
              required
              disabled={loading}
            />
          </div>
          <div className="form-group">
            <label>Amount (ACTX)</label>
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="1000"
              min="0"
              step="0.01"
              required
              disabled={loading}
            />
          </div>
          <div className="form-info">
            <span>Reward Pool Available: {rewardPool} ACTX</span>
            <span>Gas Cost: ~$0.001</span>
          </div>
          <button type="submit" className="submit-btn" disabled={loading}>
            {loading ? 'PROCESSING...' : 'DISTRIBUTE REWARD'}
          </button>
        </form>
      ) : (
        <form className="reward-form" onSubmit={handleBatchReward}>
          <div className="batch-header">
            <h3>Batch Recipients</h3>
            <button type="button" onClick={addBatchRecipient} className="add-btn" disabled={loading}>
              + Add Recipient
            </button>
          </div>
          {batchRecipients.map((recipient, index) => (
            <div key={index} className="batch-row">
              <input
                type="text"
                value={recipient.address}
                onChange={(e) => updateBatchRecipient(index, 'address', e.target.value)}
                placeholder="0x..."
                className="batch-input"
                disabled={loading}
              />
              <input
                type="number"
                value={recipient.amount}
                onChange={(e) => updateBatchRecipient(index, 'amount', e.target.value)}
                placeholder="Amount"
                min="0"
                step="0.01"
                className="batch-input"
                disabled={loading}
              />
            </div>
          ))}
          <div className="form-info">
            <span>Total: {batchRecipients.reduce((sum, r) => sum + parseFloat(r.amount || 0), 0).toLocaleString()} ACTX</span>
            <span>Gas Cost: ~$0.004 (10 recipients)</span>
          </div>
          <button type="submit" className="submit-btn" disabled={loading}>
            {loading ? 'PROCESSING...' : 'DISTRIBUTE BATCH'}
          </button>
        </form>
      )}

      <div className="recent-rewards">
        <h3>RECENT DISTRIBUTIONS</h3>
        <div className="rewards-list">
          {recentRewards.length === 0 ? (
            <p className="empty-state">No distributions yet</p>
          ) : (
            recentRewards.map((reward, index) => (
              <div key={index} className="reward-item">
                <div className="reward-info">
                  <div className="reward-address">{reward.recipient}</div>
                  <div className="reward-amount">{reward.amount} ACTX</div>
                </div>
                <div className="reward-meta">
                  <span>{reward.timestamp}</span>
                  <a 
                    href={`https://sepolia.etherscan.io/tx/${reward.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="tx-link"
                  >
                    View on Etherscan
                  </a>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

export default RewardDistribution
