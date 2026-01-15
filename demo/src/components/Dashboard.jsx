import { useEffect, useState } from 'react'
import TokenStats from './TokenStats'
import { formatTokenAmount } from '../utils/contracts'
import './Dashboard.css'

function Dashboard({ web3 }) {
  const [tokenData, setTokenData] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (web3.contract && web3.provider) {
      loadTokenData()
      const interval = setInterval(loadTokenData, 10000)
      return () => clearInterval(interval)
    } else {
      setLoading(false)
    }
  }, [web3.contract, web3.provider])

  const loadTokenData = async () => {
    if (!web3.contract) return

    try {
      const [stats, totalSupply, treasury, rewardPool, totalDistributed, taxRate, version, paused] = await Promise.all([
        web3.contract.getTokenStats().catch(() => null),
        web3.contract.totalSupply().catch(() => 0),
        web3.contract.treasuryAddress().then(addr => web3.contract.balanceOf(addr)).catch(() => 0),
        web3.contract.rewardPoolBalance().catch(() => 0),
        web3.contract.totalRewardsDistributed().catch(() => 0),
        web3.contract.taxRateBasisPoints().catch(() => 0),
        web3.contract.version().catch(() => 1),
        web3.contract.paused().catch(() => false)
      ])

      if (stats) {
        setTokenData({
          totalSupply: formatTokenAmount(stats[0]),
          treasuryBalance: formatTokenAmount(stats[1]),
          rewardPool: formatTokenAmount(stats[2]),
          totalDistributed: formatTokenAmount(stats[3]),
          taxRate: `${Number(stats[4]) / 100}%`,
          version: stats[5].toString(),
          isPaused: paused
        })
      } else {
        setTokenData({
          totalSupply: formatTokenAmount(totalSupply),
          treasuryBalance: formatTokenAmount(treasury),
          rewardPool: formatTokenAmount(rewardPool),
          totalDistributed: formatTokenAmount(totalDistributed),
          taxRate: `${Number(taxRate) / 100}%`,
          version: version.toString(),
          isPaused: paused
        })
      }
    } catch (error) {
      console.error('Error loading token data:', error)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="dashboard">
        <div className="loading">Loading contract data...</div>
      </div>
    )
  }

  if (!web3.isConnected) {
    return (
      <div className="dashboard">
        <div className="connect-prompt">
          <h2>CONNECT WALLET</h2>
          <p>Connect your MetaMask wallet to interact with the ACT.X Token contract</p>
          <button className="connect-btn-large" onClick={web3.connectWallet}>
            CONNECT WALLET
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h2>TOKEN OVERVIEW</h2>
        <p>Real-time on-chain statistics</p>
      </div>

      {tokenData && <TokenStats tokenData={tokenData} />}

      <div className="features-grid">
        <div className="feature-card">
          <div className="feature-icon">✓</div>
          <h3>UUPS Upgradeable</h3>
          <p>Future-proof architecture with proxy pattern</p>
        </div>

        <div className="feature-card">
          <div className="feature-icon">🔒</div>
          <h3>Multi-Sig Security</h3>
          <p>5 distinct roles with separation of duties</p>
        </div>

        <div className="feature-card">
          <div className="feature-icon">⚡</div>
          <h3>Gas Optimized</h3>
          <p>$0.001 per reward on Base L2</p>
        </div>

        <div className="feature-card">
          <div className="feature-icon">📊</div>
          <h3>102 Tests</h3>
          <p>Comprehensive unit, fuzz, and invariant tests</p>
        </div>

        <div className="feature-card">
          <div className="feature-icon">🔄</div>
          <h3>Transaction Tax</h3>
          <p>{tokenData?.taxRate || '2%'} recycling mechanism</p>
        </div>

        <div className="feature-card">
          <div className="feature-icon">📡</div>
          <h3>Event System</h3>
          <p>Real-time leaderboard synchronization</p>
        </div>
      </div>

      <div className="architecture-diagram">
        <h3>SYSTEM ARCHITECTURE</h3>
        <div className="flow-diagram">
          <div className="flow-step">
            <div className="flow-box">User Action</div>
            <div className="flow-arrow">→</div>
          </div>
          <div className="flow-step">
            <div className="flow-box">Backend Validation</div>
            <div className="flow-arrow">→</div>
          </div>
          <div className="flow-step">
            <div className="flow-box">RPC Node</div>
            <div className="flow-arrow">→</div>
          </div>
          <div className="flow-step">
            <div className="flow-box">Smart Contract</div>
            <div className="flow-arrow">→</div>
          </div>
          <div className="flow-step">
            <div className="flow-box">Events & Leaderboard</div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Dashboard
