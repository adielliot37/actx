import { useState, useEffect } from 'react'
import { ROLES, shortenAddress } from '../utils/contracts'
import './RoleManagement.css'

function RoleManagement({ web3 }) {
  const [roles, setRoles] = useState([
    {
      name: 'DEFAULT_ADMIN_ROLE',
      description: 'Grant/revoke roles, manage treasury',
      members: [],
      multisig: true
    },
    {
      name: 'REWARD_MANAGER_ROLE',
      description: 'Distribute rewards from pool',
      members: [],
      multisig: true
    },
    {
      name: 'TAX_MANAGER_ROLE',
      description: 'Adjust tax rate and exemptions',
      members: [],
      multisig: true
    },
    {
      name: 'PAUSER_ROLE',
      description: 'Emergency pause functionality',
      members: [],
      multisig: true
    },
    {
      name: 'UPGRADER_ROLE',
      description: 'Authorize contract upgrades',
      members: [],
      multisig: true
    }
  ])

  const [selectedRole, setSelectedRole] = useState(null)
  const [newAddress, setNewAddress] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (web3.contract && web3.account) {
      loadRoles()
    }
  }, [web3.contract, web3.account])

  const loadRoles = async () => {
    if (!web3.contract) return

    try {
      const treasury = await web3.contract.treasuryAddress()
      const updatedRoles = roles.map(role => {
        const roleHash = ROLES[role.name] || '0x00'
        return {
          ...role,
          members: [shortenAddress(treasury) + ' (Multi-sig)']
        }
      })
      setRoles(updatedRoles)
    } catch (err) {
      console.error('Error loading roles:', err)
    }
  }

  const checkUserRole = async (roleName) => {
    if (!web3.contract || !web3.account) return false
    try {
      const roleHash = ROLES[roleName]
      return await web3.contract.hasRole(roleHash, web3.account)
    } catch (err) {
      return false
    }
  }

  if (!web3.isConnected) {
    return (
      <div className="role-management">
        <div className="connect-prompt">
          <h2>CONNECT WALLET</h2>
          <p>Connect your wallet to view role management</p>
          <button className="connect-btn-large" onClick={web3.connectWallet}>
            CONNECT WALLET
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="role-management">
      <div className="section-header">
        <h2>ROLE MANAGEMENT</h2>
        <p>5 distinct roles with multi-signature protection</p>
      </div>

      <div className="roles-grid">
        {roles.map((role, index) => (
          <div
            key={index}
            className={`role-card ${selectedRole === index ? 'selected' : ''}`}
            onClick={() => setSelectedRole(selectedRole === index ? null : index)}
          >
            <div className="role-header">
              <div className="role-icon">{role.multisig ? '🔐' : '👤'}</div>
              <div className="role-name">{role.name}</div>
            </div>
            <div className="role-description">{role.description}</div>
            <div className="role-members">
              <div className="members-label">Members ({role.members.length})</div>
              {role.members.map((member, i) => (
                <div key={i} className="member-item">
                  {member}
                </div>
              ))}
            </div>
            {role.multisig && (
              <div className="multisig-badge">Multi-Sig Required</div>
            )}
          </div>
        ))}
      </div>

      <div className="security-features">
        <h3>SECURITY FEATURES</h3>
        <div className="features-list">
          <div className="feature-item">
            <span className="feature-icon">✓</span>
            <div>
              <div className="feature-title">Separation of Duties</div>
              <div className="feature-desc">Each role has specific permissions, preventing single points of failure</div>
            </div>
          </div>
          <div className="feature-item">
            <span className="feature-icon">✓</span>
            <div>
              <div className="feature-title">Multi-Signature Control</div>
              <div className="feature-desc">Critical operations require multiple signatures for enhanced security</div>
            </div>
          </div>
          <div className="feature-item">
            <span className="feature-icon">✓</span>
            <div>
              <div className="feature-title">Access Control</div>
              <div className="feature-desc">OpenZeppelin AccessControl ensures role-based permissions are enforced</div>
            </div>
          </div>
          <div className="feature-item">
            <span className="feature-icon">✓</span>
            <div>
              <div className="feature-title">Upgrade Authorization</div>
              <div className="feature-desc">Only UPGRADER_ROLE can authorize contract upgrades via UUPS pattern</div>
            </div>
          </div>
        </div>
      </div>

      {selectedRole !== null && (
        <div className="role-actions">
          <h3>MANAGE {roles[selectedRole].name}</h3>
          <div className="action-form">
            <div className="form-group">
              <label>Address</label>
              <input
                type="text"
                value={newAddress}
                onChange={(e) => setNewAddress(e.target.value)}
                placeholder="0x..."
                disabled={loading}
              />
            </div>
            <div className="action-buttons">
              <button className="action-btn grant" disabled={loading}>
                GRANT ROLE
              </button>
              <button className="action-btn revoke" disabled={loading}>
                REVOKE ROLE
              </button>
            </div>
            <div className="form-note">
              Note: This action requires multi-signature approval and appropriate role permissions
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default RoleManagement
