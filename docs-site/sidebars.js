/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Infrastructure',
      items: ['architecture', 'roadmap'],
    },
    {
      type: 'category',
      label: 'Operations',
      items: ['runbook', 'patching'],
    },
    {
      type: 'category',
      label: 'Services',
      items: [
        'services/traefik',
        'services/monitoring',
        'services/arr-stack',
        'services/media',
        'services/sdr-scanner',
        'services/wireguard',
        'services/home-assistant',
        'services/authentik',
        'services/kanboard',
        'services/mailserver',
        'services/remote-desktop',
      ],
    },
    {
      type: 'category',
      label: 'Kubernetes',
      items: ['kubernetes/talos', 'kubernetes/workloads'],
    },
    {
      type: 'category',
      label: 'ShopStack Operations',
      items: [
        'consulting-ops/index',
        'consulting-ops/shopstack-deployment',
        'consulting-ops/client-onboarding',
        'consulting-ops/inbound-lead-response',
        'consulting-ops/linkedin-posting',
        'consulting-ops/facebook-content',
        'consulting-ops/monthly-business-review',
        'consulting-ops/client-support',
      ],
    },
  ],
};

export default sidebars;
