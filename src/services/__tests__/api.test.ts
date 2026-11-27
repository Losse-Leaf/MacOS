import { describe, expect, it } from 'vitest'
import { buildOIDCLoginUrl, parsePairLink, resolveMediaUrl } from '../api'

describe('api auth & url helpers', () => {
  it('builds valid OIDC login URL', () => {
    const url = buildOIDCLoginUrl('https://leaf.starryheavens.uk/', 'My MacBook')
    expect(url).toBe(
      'https://leaf.starryheavens.uk/api/v1/auth/oidc/login?platform=macos&device_name=My+MacBook',
    )
    expect(buildOIDCLoginUrl('invalid-url', 'Mac')).toBeNull()
  })

  it('parses both OAuth callback and legacy pair deep links', () => {
    expect(parsePairLink('looseleaf://auth/callback?hub=https%3A%2F%2Fleaf.example.com&code=abc123')).toEqual({
      hub: 'https://leaf.example.com',
      code: 'abc123',
    })
    expect(parsePairLink('looseleaf://pair?hub=https://a.com&ticket=xyz')).toEqual({
      hub: 'https://a.com',
      code: 'xyz',
    })
    expect(parsePairLink('https://leaf.example.com')).toBeNull()
  })

  it('resolves relative and absolute media URLs cleanly', () => {
    expect(resolveMediaUrl('/media/entries/a.jpg', 'https://leaf.starryheavens.uk/')).toBe(
      'https://leaf.starryheavens.uk/media/entries/a.jpg',
    )
    expect(resolveMediaUrl('https://cdn.example.com/1.png', 'https://leaf.starryheavens.uk')).toBe(
      'https://cdn.example.com/1.png',
    )
    expect(resolveMediaUrl('', 'https://leaf.starryheavens.uk')).toBe('')
  })
})
