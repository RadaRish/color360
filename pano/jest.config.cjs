module.exports = {
  testEnvironment: 'jsdom',
  testEnvironmentOptions: { url: 'http://localhost/' },
  roots: ['<rootDir>/tests'],
  testMatch: ['**/tests/(smoke|hotspot_manager).test.js'],
  transform: {},
  verbose: true,
};
