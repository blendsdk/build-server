import { defineConfig } from 'vitepress'

export default defineConfig({
  base: '/build-server/',
  title: 'Build Server',
  description:
    'Self-hosted GitHub Actions runner fleet with an isolated Docker daemon inside every runner',
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['meta', { property: 'og:type', content: 'website' }],
    ['meta', { property: 'og:title', content: 'Build Server' }],
    [
      'meta',
      {
        property: 'og:description',
        content:
          'Self-hosted GitHub Actions runner fleet with an isolated Docker daemon inside every runner'
      }
    ],
    [
      'meta',
      { property: 'og:image', content: 'https://blendsdk.github.io/build-server/social-preview.png' }
    ],
    ['meta', { name: 'twitter:card', content: 'summary_large_image' }],
    [
      'meta',
      {
        name: 'twitter:image',
        content: 'https://blendsdk.github.io/build-server/social-preview.png'
      }
    ]
  ],
  themeConfig: {
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Architecture', link: '/architecture/overview' },
      { text: 'Operations', link: '/operations/upgrades' },
      { text: 'Reference', link: '/reference/files' }
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Guide',
          items: [
            { text: 'Getting started', link: '/guide/getting-started' },
            { text: 'Organizations', link: '/guide/organizations' },
            { text: 'Admin CLI', link: '/guide/cli' },
            { text: 'Custom images', link: '/guide/custom-images' },
            { text: 'Runner versions', link: '/guide/runner-version' }
          ]
        }
      ],
      '/architecture/': [
        {
          text: 'Architecture',
          items: [
            { text: 'Overview', link: '/architecture/overview' },
            { text: 'Path resolution', link: '/architecture/path-resolution' },
            { text: 'Security model', link: '/architecture/security' }
          ]
        }
      ],
      '/operations/': [
        {
          text: 'Operations',
          items: [
            { text: 'Upgrades and changes', link: '/operations/upgrades' },
            { text: 'Troubleshooting', link: '/operations/troubleshooting' }
          ]
        }
      ],
      '/reference/': [
        {
          text: 'Reference',
          items: [
            { text: 'Files and variables', link: '/reference/files' },
            { text: 'Testing', link: '/reference/testing' },
            { text: 'FAQ', link: '/reference/faq' }
          ]
        }
      ]
    },
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: 'https://github.com/blendsdk/build-server' }],
    editLink: {
      pattern: 'https://github.com/blendsdk/build-server/edit/main/docs/:path',
      text: 'Edit this page on GitHub'
    },
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2026 blendsdk'
    }
  }
})
