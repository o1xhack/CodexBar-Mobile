import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ProviderPluginCookieHeaderEchoTests {
    @Test(arguments: BundledPluginTestSupport.engines)
    func `host echoes the selected session cookie without exposing its value`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          if (session.header !== undefined || session.records !== undefined) throw new Error('cookie exposed');
          await ctx.http.get('https://example.test/api', {cookieSession: session.id});
          return {identity: {loginMethod: 'Browser session'}};
        }
        """, transport: ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "X-Console-Csrf") == "synthetic-csrf")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "session=fixture; csrf=synthetic-csrf")
            let url = try #require(request.url)
            return try (Data("{}".utf8), #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        })
        _ = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
            .init(header: "session=fixture; csrf=synthetic-csrf", source: "Synthetic", origin: "https://example.test")
        })
    }

    @Test(arguments: [
        "{origin:'https://other.test',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'http://example.test',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test:444',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test/api',cookie:'csrf',header:'X-Csrf'}",
        "{origin:'https://example.test',cookie:'undeclared',header:'X-Csrf'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Cookie'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Host'}",
        "{origin:'https://example.test',cookie:'csrf',header:'Authorization'}",
        "{origin:'https://example.test',cookie:'csrf',header:'X-Csrf',extra:true}",
    ], BundledPluginTestSupport.engines)
    func `echo authority rejects undeclared origins cookies and unsafe headers`(
        echo: String, engine: ProviderPluginEngineKind)
    {
        #expect(throws: ProviderPluginError.self) {
            try ProviderPluginRuntime(source: """
            defineProvider({id:'longcat',name:'Synthetic',settings:[],endpoints:['https://example.test'],
              capabilities:['browser-cookies'],cookieDomains:['example.test'],
              cookiePolicy:{selection:'request-url',cache:'nonpersistent',requiredCookies:['csrf'],headerEcho:\(echo)},
              async fetchUsage(){return {empty:true}}});
            """, engine: engine)
        }
    }

    @Test(
        arguments: ["session=fixture", "session=fixture; csrf=one; csrf=two", "session=fixture; csrf="],
        BundledPluginTestSupport.engines)
    func `missing empty and ambiguous echo cookies fail before transport`(
        header: String, engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                .init(header: header, source: "Synthetic", origin: "https://example.test")
            })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `scripts cannot override the host echo header even with different casing`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test/api', {cookieSession:session.id,headers:{'x-console-csrf':'forged'}});
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                .init(header: "session=fixture; csrf=synthetic", source: "Synthetic", origin: "https://example.test")
            })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `echo is absent on another declared origin`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://other.test/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: ProviderHTTPTransportHandler { request in
            #expect(request.value(forHTTPHeaderField: "X-Console-Csrf") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == "csrf=other-fixture")
            let url = try #require(request.url)
            return try (Data("{}".utf8), #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        })
        let other = try Self.record("csrf", "other-fixture", domain: "other.test")
        _ = try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
            .init(header: "", source: "Synthetic", origin: "https://example.test", records: [other])
        })
    }

    @Test(arguments: ["/private", "/expired"], BundledPluginTestSupport.engines)
    func `echo respects cookie paths and expiration`(path: String, engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        let records = try [
            Self.record("session", "fixture"),
            Self.record(
                "csrf",
                "synthetic",
                path: path == "/expired" ? "/" : path,
                expires: path == "/expired" ? Date(timeIntervalSince1970: 1) : nil),
        ]
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                .init(header: "", source: "Synthetic", origin: "https://example.test", records: records)
            })
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `record backed sessions reject another declared port before echo transport`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine: engine, script: """
        for await (const session of ctx.browser.sessions('example.test')) {
          await ctx.http.get('https://example.test:444/api', {cookieSession:session.id});
          return {empty:true};
        }
        """, transport: Self.deniedTransport)
        let record = try Self.record("csrf", "synthetic")
        await #expect(throws: (any Error).self) {
            try await runtime.fetchUsage(cookieSessionResolver: { _, _ in
                .init(header: "", source: "Synthetic", origin: "https://example.test", records: [record])
            })
        }
    }

    @Test
    func `redirects reselect echo and never retain an out of scope value`() throws {
        let runtime = try Self.runtime(
            engine: .quickJS,
            script: "return {empty:true};",
            transport: Self.deniedTransport)
        let jar = ProviderPluginCookieJar(headerEcho: runtime.manifest.cookiePolicy?.headerEcho)
        let session = try ProviderPluginCookieSession(
            header: "", source: "Synthetic", origin: "https://example.test", records: [
                Self.record("session", "fixture"), Self.record("csrf", "synthetic", path: "/api"),
            ])
        jar.register(session)
        let delegate = ProviderPluginCookieTransport.CookieRedirectDelegate(jar: jar, id: session.id)
        let origin = try #require(URL(string: "https://example.test/api/one"))
        for (target, allowed) in [
            ("https://example.test/api/two", true), ("https://example.test/elsewhere", false),
            ("https://other.test/api", false), ("https://example.test:444/api", false),
            ("http://example.test/api", false), ("https://user:pass@example.test/api", false),
        ] {
            let url = try #require(URL(string: target))
            var request = URLRequest(url: url)
            request.setValue("stale", forHTTPHeaderField: "X-Console-Csrf")
            let redirected = delegate.redirectedRequest(originalURL: origin, request: request)
            #expect((redirected != nil) == allowed)
            if allowed { #expect(redirected?.value(forHTTPHeaderField: "X-Console-Csrf") == "synthetic") }
        }
    }

    private static func record(
        _ name: String, _ value: String, domain: String = "example.test", path: String = "/", expires: Date? = nil)
        throws -> ProviderPluginCookieRecord
    {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE",
        ]
        if let expires { properties[.expires] = expires }
        let cookie = try #require(HTTPCookie(properties: properties))
        return ProviderPluginCookieRecord(cookie: cookie)
    }

    private static let deniedTransport = ProviderHTTPTransportHandler { _ in
        Issue.record("Denied echo request reached transport")
        throw URLError(.badURL)
    }

    private static func runtime(
        engine: ProviderPluginEngineKind, script: String, transport: any ProviderHTTPTransport) throws
        -> ProviderPluginRuntime
    {
        try ProviderPluginRuntime(source: """
        defineProvider({id:'longcat',name:'Synthetic',settings:[],
          endpoints:['https://example.test','https://example.test:444','https://other.test'],
          capabilities:['browser-cookies'],cookieDomains:['example.test','other.test'],
          cookiePolicy:{selection:'request-url',cache:'nonpersistent',requiredCookies:['csrf'],
            headerEcho:{origin:'https://example.test',cookie:'csrf',header:'X-Console-Csrf'}},
          async fetchUsage(ctx){\(script)}});
        """, transport: transport, engine: engine)
    }
}
