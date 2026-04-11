import { defineConfig, devices, type ReporterDescription } from "@playwright/test"

const port = Number(process.env.PLAYWRIGHT_PORT ?? 3000)
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? `http://127.0.0.1:${port}`
const serverHost = process.env.PLAYWRIGHT_SERVER_HOST ?? "127.0.0.1"
const serverPort = process.env.PLAYWRIGHT_SERVER_PORT ?? "4096"
const command = `bun run dev -- --host 0.0.0.0 --port ${port}`
const reuse = !process.env.CI
const managed = process.env.PLAYWRIGHT_MANAGED_WEB_SERVER !== "0"
const workers = Number(process.env.PLAYWRIGHT_WORKERS ?? (process.env.CI ? 5 : 0)) || undefined
const reporter: ReporterDescription[] = [["html", { outputFolder: "e2e/playwright-report", open: "never" }], ["line"]]

if (process.env.PLAYWRIGHT_JUNIT_OUTPUT) {
  reporter.push(["junit", { outputFile: process.env.PLAYWRIGHT_JUNIT_OUTPUT }])
}

// Longer timeouts for slower CI runners (GitHub-hosted vs Blacksmith)
// Windows runners are significantly slower and need more time
const isWindows = process.platform === "win32"
const testTimeout = process.env.CI ? (isWindows ? 150_000 : 120_000) : 60_000
const expectTimeout = process.env.CI ? (isWindows ? 30_000 : 20_000) : 10_000

export default defineConfig({
  testDir: "./e2e",
  outputDir: "./e2e/test-results",
  timeout: testTimeout,
  expect: {
    timeout: expectTimeout,
  },
  fullyParallel: process.env.PLAYWRIGHT_FULLY_PARALLEL === "1",
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers,
  reporter,
  webServer: managed
    ? {
        command,
        url: baseURL,
        reuseExistingServer: reuse,
        timeout: 120_000,
        env: {
          VITE_OPENCODE_SERVER_HOST: serverHost,
          VITE_OPENCODE_SERVER_PORT: serverPort,
        },
      }
    : undefined,
  use: {
    baseURL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
})
