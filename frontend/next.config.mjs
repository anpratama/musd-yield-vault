/** @type {import("next").NextConfig} */

const nextConfig = {
  webpack: (config) => {
    // RainbowKit / wagmi need these node polyfills excluded on the client
    config.resolve.fallback = { fs: false, net: false, tls: false };
    config.externals.push("pino-pretty", "lokijs", "encoding");
    // Stub out optional x402 payment modules pulled in transitively by
    // @coinbase/cdp-sdk (via wagmi's baseAccount connector). They are only
    // used by x402 payment flows, which this app never touches.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@x402/core/client": false,
      "@x402/svm/exact/client": false,
      "@x402/evm": false,
    };
    return config;
  },
};

export default nextConfig;
