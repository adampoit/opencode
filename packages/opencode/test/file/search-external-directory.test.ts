import { describe, expect, test } from "bun:test"
import path from "path"
import { Effect } from "effect"
import * as File from "../../src/file"
import * as Session from "../../src/session/session"
import { provideTestInstance, tmpdir } from "../fixture/fixture"

const search = (input: { query: string; type?: "file" | "directory"; sessionID?: string; limit?: number }) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const svc = yield* File.Service
      return yield* svc.search(input)
    }).pipe(Effect.provide(File.defaultLayer)),
  )

const create = () =>
  Effect.runPromise(
    Effect.gen(function* () {
      const svc = yield* Session.Service
      return yield* svc.create({})
    }).pipe(Effect.provide(Session.defaultLayer)),
  )

const addDirectory = (input: { sessionID: Session.Info["id"]; path: string }) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const svc = yield* Session.Service
      return yield* svc.addWorkspaceDirectory(input)
    }).pipe(Effect.provide(Session.defaultLayer)),
  )

const setPermission = (input: {
  sessionID: Session.Info["id"]
  permission: Array<{ permission: string; pattern: string; action: string }>
}) =>
  Effect.runPromise(
    Effect.gen(function* () {
      const svc = yield* Session.Service
      return yield* svc.setPermission(input as never)
    }).pipe(Effect.provide(Session.defaultLayer)),
  )

describe("file.search external directories", () => {
  test("does not include external files without sessionID", async () => {
    await using outside = await tmpdir({
      init: async (dir) => {
        await Bun.write(path.join(dir, "external-only.txt"), "outside")
      },
    })
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const result = await search({
          query: "external-only",
          type: "file",
          limit: 20,
        })

        expect(result.some((item: string) => item.includes("external-only.txt"))).toBe(false)
      },
    })
  })

  test("includes external files with sessionID permission", async () => {
    await using outside = await tmpdir({
      init: async (dir) => {
        await Bun.write(path.join(dir, "external-match.txt"), "outside")
      },
    })
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const session = await create()
        await addDirectory({
          sessionID: session.id,
          path: outside.path,
        })

        const result = await search({
          query: "external-match",
          type: "file",
          sessionID: session.id,
          limit: 20,
        })

        expect(result.some((item: string) => item.includes("external-match.txt"))).toBe(true)
      },
    })
  })

  test("ignores broad external_directory patterns", async () => {
    await using outside = await tmpdir({
      init: async (dir) => {
        await Bun.write(path.join(dir, "broad-pattern.txt"), "outside")
      },
    })
    await using project = await tmpdir({ git: true })

    await provideTestInstance({
      directory: project.path,
      fn: async () => {
        const session = await create()
        await setPermission({
          sessionID: session.id,
          permission: [{ permission: "external_directory", pattern: "*", action: "allow" }],
        })

        const result = await search({
          query: "broad-pattern",
          type: "file",
          sessionID: session.id,
          limit: 20,
        })

        expect(result.some((item: string) => item.includes("broad-pattern.txt"))).toBe(false)
      },
    })
  })
})
