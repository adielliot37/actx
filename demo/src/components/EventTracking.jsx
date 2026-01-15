import { useState, useEffect } from 'react'
import { formatTokenAmount, shortenAddress } from '../utils/contracts'
import './EventTracking.css'

function EventTracking({ web3 }) {
  const [events, setEvents] = useState([])
  const [filter, setFilter] = useState('all')
  const [leaderboard, setLeaderboard] = useState([])

  useEffect(() => {
    if (web3.contract && web3.provider) {
      loadEvents()
      setupEventListeners()
    }
  }, [web3.contract, web3.provider])

  const loadEvents = async () => {
    if (!web3.contract || !web3.provider) return

    try {
      const currentBlock = await web3.provider.getBlockNumber()
      const fromBlock = Math.max(0, currentBlock - 10000)
      
      const filterReward = web3.contract.filters.RewardDistributed()
      const filterTax = web3.contract.filters.TaxCollected()
      
      const [rewardEvents, taxEvents] = await Promise.all([
        web3.provider.getLogs({
          address: web3.contract.target,
          fromBlock: fromBlock,
          toBlock: 'latest',
          topics: filterReward?.topics || []
        }).catch(() => []),
        web3.provider.getLogs({
          address: web3.contract.target,
          fromBlock: fromBlock,
          toBlock: 'latest',
          topics: filterTax?.topics || []
        }).catch(() => [])
      ])

      const parsedRewards = rewardEvents
        .map(log => {
          try {
            const parsed = web3.contract.interface.parseLog(log)
            if (!parsed || !parsed.args) return null
            
            const recipient = parsed.args.recipient
            const amount = parsed.args.amount
            const poolRemaining = parsed.args.rewardPoolRemaining
            const timestamp = parsed.args.timestamp
            
            if (!recipient || amount === null || amount === undefined) {
              return null
            }
            
            return {
              type: 'RewardDistributed',
              recipient: shortenAddress(recipient),
              amount: formatTokenAmount(amount),
              poolRemaining: formatTokenAmount(poolRemaining || 0),
              timestamp: timestamp ? new Date(Number(timestamp) * 1000).toLocaleString() : new Date().toLocaleString(),
              txHash: log.transactionHash
            }
          } catch (err) {
            console.warn('Failed to parse reward event:', err)
            return null
          }
        })
        .filter(event => event !== null)
        .slice(-10)

      const parsedTaxes = taxEvents
        .map(log => {
          try {
            const parsed = web3.contract.interface.parseLog(log)
            if (!parsed || !parsed.args) return null
            
            const from = parsed.args.from
            const to = parsed.args.to
            const taxAmount = parsed.args.taxAmount
            const netAmount = parsed.args.netAmount
            
            if (!from || !to || taxAmount === null || taxAmount === undefined || netAmount === null || netAmount === undefined) {
              return null
            }
            
            return {
              type: 'TaxCollected',
              from: shortenAddress(from),
              to: shortenAddress(to),
              taxAmount: formatTokenAmount(taxAmount),
              netAmount: formatTokenAmount(netAmount),
              timestamp: new Date().toLocaleString(),
              txHash: log.transactionHash
            }
          } catch (err) {
            console.warn('Failed to parse tax event:', err)
            return null
          }
        })
        .filter(event => event !== null)
        .slice(-10)

      const allEvents = [...parsedRewards, ...parsedTaxes]
      if (allEvents.length > 0) {
        setEvents(allEvents.sort((a, b) => {
          try {
            return new Date(b.timestamp) - new Date(a.timestamp)
          } catch {
            return 0
          }
        }).slice(0, 20))
      }

      const leaderboardData = parsedRewards.reduce((acc, event) => {
        if (!event || !event.recipient) return acc
        const addr = event.recipient
        if (!acc[addr]) {
          acc[addr] = { address: addr, totalRewards: 0 }
        }
        try {
          const amount = parseFloat(event.amount.replace(/,/g, '')) || 0
          acc[addr].totalRewards += amount
        } catch {
          // Skip invalid amounts
        }
        return acc
      }, {})

      setLeaderboard(
        Object.values(leaderboardData)
          .sort((a, b) => b.totalRewards - a.totalRewards)
          .slice(0, 10)
          .map((entry, index) => ({
            ...entry,
            rank: index + 1,
            totalRewards: entry.totalRewards.toLocaleString()
          }))
      )
    } catch (err) {
      console.error('Error loading events:', err)
    }
  }

  const setupEventListeners = () => {
    if (!web3.contract) return

    const handleRewardDistributed = (recipient, amount, poolRemaining, timestamp) => {
      try {
        const newEvent = {
          type: 'RewardDistributed',
          recipient: shortenAddress(recipient),
          amount: formatTokenAmount(amount),
          poolRemaining: formatTokenAmount(poolRemaining),
          timestamp: new Date(Number(timestamp) * 1000).toLocaleString(),
          txHash: 'pending'
        }
        setEvents(prev => [newEvent, ...prev].slice(0, 20))
        setTimeout(loadEvents, 2000)
      } catch (err) {
        console.error('Error handling RewardDistributed event:', err)
      }
    }

    const handleTaxCollected = (from, to, taxAmount, netAmount) => {
      try {
        const newEvent = {
          type: 'TaxCollected',
          from: shortenAddress(from),
          to: shortenAddress(to),
          taxAmount: formatTokenAmount(taxAmount),
          netAmount: formatTokenAmount(netAmount),
          timestamp: new Date().toLocaleString(),
          txHash: 'pending'
        }
        setEvents(prev => [newEvent, ...prev].slice(0, 20))
      } catch (err) {
        console.error('Error handling TaxCollected event:', err)
      }
    }

    try {
      web3.contract.on('RewardDistributed', handleRewardDistributed)
      web3.contract.on('TaxCollected', handleTaxCollected)
    } catch (err) {
      console.error('Error setting up event listeners:', err)
    }

    return () => {
      try {
        if (web3.contract) {
          web3.contract.off('RewardDistributed', handleRewardDistributed)
          web3.contract.off('TaxCollected', handleTaxCollected)
        }
      } catch (err) {
        console.error('Error removing event listeners:', err)
      }
    }
  }

  const filteredEvents = filter === 'all' 
    ? events 
    : events.filter(e => e.type === filter)

  if (!web3.isConnected) {
    return (
      <div className="event-tracking">
        <div className="connect-prompt">
          <h2>CONNECT WALLET</h2>
          <p>Connect your wallet to view events</p>
          <button className="connect-btn-large" onClick={web3.connectWallet}>
            CONNECT WALLET
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="event-tracking">
      <div className="section-header">
        <h2>EVENT TRACKING & LEADERBOARD</h2>
        <p>Real-time on-chain events for leaderboard synchronization</p>
      </div>

      <div className="tracking-grid">
        <div className="events-panel">
          <div className="panel-header">
            <h3>LIVE EVENTS</h3>
            <div className="filter-buttons">
              <button
                className={filter === 'all' ? 'active' : ''}
                onClick={() => setFilter('all')}
              >
                All
              </button>
              <button
                className={filter === 'RewardDistributed' ? 'active' : ''}
                onClick={() => setFilter('RewardDistributed')}
              >
                Rewards
              </button>
              <button
                className={filter === 'TaxCollected' ? 'active' : ''}
                onClick={() => setFilter('TaxCollected')}
              >
                Taxes
              </button>
            </div>
          </div>

          <div className="events-list">
            {filteredEvents.length === 0 ? (
              <p className="empty-state">No events found</p>
            ) : (
              filteredEvents.map((event, index) => (
                <div key={index} className={`event-item ${event.type}`}>
                  <div className="event-header">
                    <div className="event-type">{event.type}</div>
                    <div className="event-time">{event.timestamp}</div>
                  </div>
                  <div className="event-details">
                    {event.type === 'RewardDistributed' ? (
                      <>
                        <div className="event-row">
                          <span>Recipient:</span>
                          <span className="event-value">{event.recipient}</span>
                        </div>
                        <div className="event-row">
                          <span>Amount:</span>
                          <span className="event-value">{event.amount} ACTX</span>
                        </div>
                        <div className="event-row">
                          <span>Pool Remaining:</span>
                          <span className="event-value">{event.poolRemaining} ACTX</span>
                        </div>
                      </>
                    ) : (
                      <>
                        <div className="event-row">
                          <span>From:</span>
                          <span className="event-value">{event.from}</span>
                        </div>
                        <div className="event-row">
                          <span>To:</span>
                          <span className="event-value">{event.to}</span>
                        </div>
                        <div className="event-row">
                          <span>Tax:</span>
                          <span className="event-value tax-amount">-{event.taxAmount} ACTX</span>
                        </div>
                        <div className="event-row">
                          <span>Net:</span>
                          <span className="event-value net-amount">{event.netAmount} ACTX</span>
                        </div>
                      </>
                    )}
                    {event.txHash !== 'pending' && (
                      <div className="event-tx">
                        <a 
                          href={`https://sepolia.etherscan.io/tx/${event.txHash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="tx-link"
                        >
                          View on Etherscan
                        </a>
                      </div>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="leaderboard-panel">
          <div className="panel-header">
            <h3>LEADERBOARD</h3>
            <div className="leaderboard-stats">
              <span>Total Participants: {leaderboard.length}</span>
            </div>
          </div>

          <div className="leaderboard-list">
            {leaderboard.length === 0 ? (
              <p className="empty-state">No leaderboard data yet</p>
            ) : (
              leaderboard.map((entry, index) => (
                <div key={index} className="leaderboard-item">
                  <div className="rank-badge">{entry.rank}</div>
                  <div className="leaderboard-info">
                    <div className="leaderboard-address">{entry.address}</div>
                    <div className="leaderboard-rewards">{entry.totalRewards} ACTX</div>
                  </div>
                  {entry.rank <= 3 && (
                    <div className="trophy">🏆</div>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default EventTracking
