import { describe, expect, it } from 'vitest'
import { compareSemver, parseChecksumText, parseReleaseInfo } from '../updater'

describe('macOS updater helpers', () => {
  it('compares semantic versions accurately', () => {
    expect(compareSemver('4.2.0', '4.1.0')).toBe(1)
    expect(compareSemver('v4.2.0', '4.2.0')).toBe(0)
    expect(compareSemver('4.1.9', '4.2.0')).toBe(-1)
    expect(compareSemver('4.10.0', '4.2.0')).toBe(1)
  })

  it('parses SHA-256 checksum files and asset lines', () => {
    const hash = 'a'.repeat(64)
    expect(parseChecksumText(`${hash}  LooseLeaf-v4.2.0-arm64.zip\n`, 'LooseLeaf-v4.2.0-arm64.zip')).toBe(hash)
    expect(parseChecksumText(`${hash}\n`, 'LooseLeaf-v4.2.0-arm64.zip')).toBe(hash)
    expect(parseChecksumText('invalid line', 'LooseLeaf-v4.2.0-arm64.zip')).toBeNull()
  })

  it('extracts macOS arm64 zip release info and fallback checksum asset', () => {
    const hash = 'b'.repeat(64)
    const parsed = parseReleaseInfo(
      {
        tag_name: 'v4.2.0',
        body: '内置应用内一键更新。',
        published_at: '2026-11-28T08:30:00Z',
        assets: [
          {
            name: 'LooseLeaf-v4.2.0-arm64.zip',
            browser_download_url: 'https://github.com/Losse-Leaf/MacOS/releases/download/v4.2.0/LooseLeaf-v4.2.0-arm64.zip',
            digest: `sha256:${hash}`,
          },
          {
            name: 'LooseLeaf-v4.2.0-arm64.zip.sha256',
            browser_download_url: 'https://github.com/Losse-Leaf/MacOS/releases/download/v4.2.0/LooseLeaf-v4.2.0-arm64.zip.sha256',
          },
        ],
      },
      '4.1.0',
    )

    expect(parsed.missingAsset).toBe(false)
    expect(parsed.update).toMatchObject({
      tagName: 'v4.2.0',
      version: '4.2.0',
      expectedSha256: hash,
      assetName: 'LooseLeaf-v4.2.0-arm64.zip',
    })

    const upToDate = parseReleaseInfo(
      {
        tag_name: 'v4.2.0',
        assets: [],
      },
      '4.2.0',
    )
    expect(upToDate).toEqual({ update: null, missingAsset: false })
  })
})
