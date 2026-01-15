import './TokenStats.css'

function TokenStats({ tokenData }) {
  const stats = [
    { label: 'Total Supply', value: `${tokenData.totalSupply} ACTX`, icon: '📦' },
    { label: 'Treasury Balance', value: `${tokenData.treasuryBalance} ACTX`, icon: '🏦' },
    { label: 'Reward Pool', value: `${tokenData.rewardPool} ACTX`, icon: '🎁' },
    { label: 'Total Distributed', value: `${tokenData.totalDistributed} ACTX`, icon: '📤' },
    { label: 'Tax Rate', value: tokenData.taxRate, icon: '💸' },
    { label: 'Contract Version', value: `v${tokenData.version}`, icon: '🔢' }
  ]

  return (
    <div className="token-stats">
      {stats.map((stat, index) => (
        <div key={index} className="stat-card">
          <div className="stat-icon">{stat.icon}</div>
          <div className="stat-content">
            <div className="stat-label">{stat.label}</div>
            <div className="stat-value">{stat.value}</div>
          </div>
        </div>
      ))}
    </div>
  )
}

export default TokenStats

