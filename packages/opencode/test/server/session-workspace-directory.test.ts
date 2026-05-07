import { describe, expect, test } from "bun:test"
import { Effect } from "effect"
import * as Session from "../../src/session/session"
import { Server } from "../../src/server/server"
import { provideTestInstance, tmpdir } from "../fixture/fixture"

const create = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const svc = yield* Session.Service
      return yield* svc.create({})
    }).pipe(Effect.provide(Session.defaultLayer)),
  )

describe("session.workspaceDirectory endpoint", () => {
  test("adds external directory for a session", async () => {
    await using outside = await tmpdir({})
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const session = await create()
        const app = Server.Default().app
        const response = await app.request(
          `/session/${session.id}/workspace/directory?directory=${encodeURIComponent(project.path)}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ path: outside.path }),
          },
        )

        expect(response.status).toBe(200)

        const body = (await response.json()) as {
          added: boolean
          directory: string
          glob: string
          session: { id: string }
        }
        expect(body.added).toBe(true)
        expect(body.directory).toBe(outside.path)
        expect(body.glob.endsWith("/*")).toBe(true)
        expect(body.session.id).toBe(session.id)

        const second = await app.request(
          `/session/${session.id}/workspace/directory?directory=${encodeURIComponent(project.path)}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ path: outside.path }),
          },
        )

        expect(second.status).toBe(200)
        const duplicate = (await second.json()) as { added: boolean }
        expect(duplicate.added).toBe(false)
      },
    })
  })

  test("validates request body", async () => {
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const session = await create()
        const app = Server.Default().app
        const response = await app.request(
          `/session/${session.id}/workspace/directory?directory=${encodeURIComponent(project.path)}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({}),
          },
        )

        expect(response.status).toBe(400)
      },
    })
  })

  test("returns not found for missing directory", async () => {
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const session = await create()
        const app = Server.Default().app
        const response = await app.request(
          `/session/${session.id}/workspace/directory?directory=${encodeURIComponent(project.path)}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ path: `${project.path}/missing` }),
          },
        )

        expect(response.status).toBe(404)
      },
    })
  })
})
