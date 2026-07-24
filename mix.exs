defmodule HexpmMcp.MixProject do
  use Mix.Project

  @source_url "https://github.com/joshrotenberg/hexpm-mcp"

  def project do
    [
      app: :hexpm_mcp,
      version: "0.3.4",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      releases: releases(),
      tinfoil: tinfoil(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {HexpmMcp.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "MCP server for hex.pm and hexdocs.pm: search, inspect, compare, audit, and " <>
      "discover Elixir/Erlang packages, browse docs, and check dependencies for vulnerabilities."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Josh Rotenberg"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url
    ]
  end

  defp deps do
    [
      {:anubis_mcp, "~> 1.0"},
      {:bandit, "~> 1.0"},
      # 0.2.1 for Cheer.parse/3 and Cheer.argv/0; 0.2.0 has neither.
      dep(:cheer, "~> 0.2.1", "CHEER_PATH"),
      dep(:tinfoil, "~> 0.2", "TINFOIL_PATH", runtime: false),
      # Optional so consumers using this as a library don't inherit the build
      # tooling. Always installed for this project, which is what the release
      # needs. Runtime calls are guarded with Code.ensure_loaded?/1.
      #
      # Held at 1.5.x. 1.6.0 boots the release through `-s elixir start_cli`,
      # so Elixir's own CLI claims --version and --help and treats the first
      # remaining argument as a script path: `hexpm_mcp --transport stdio`
      # fails with "No file named --transport". Reproduces on tinfoil_demo too,
      # so it is not specific to this project.
      {:burrito, "~> 1.5.0", optional: true},
      {:req, "~> 0.6"},
      {:floki, "~> 0.37"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  # Resolve a dependency against a local checkout when the given env var is set,
  # and against Hex otherwise. Lets cheer and tinfoil be co-developed alongside
  # this project without committing path deps:
  #
  #     CHEER_PATH=../cheer mix deps.get
  #
  defp dep(app, requirement, env_var, opts \\ []) do
    case System.get_env(env_var) do
      nil -> {app, requirement, opts}
      path -> {app, [path: path] ++ opts}
    end
  end

  defp releases do
    [
      hexpm_mcp: [
        applications: [runtime_tools: :permanent],
        # Only wrap when Burrito is actually driving the build. `mix tinfoil.build`
        # always sets BURRITO_TARGET; the Dockerfile never does, so the Fly image
        # keeps getting a plain assembled release from the same release entry.
        #
        # This has to stay a single release named hexpm_mcp: Tinfoil.Build runs
        # `mix release` with no name and reads burrito_out/<app>_<target>, so a
        # second burrito-only release entry would break both halves.
        steps: release_steps(),
        burrito: [
          targets: [
            darwin_arm64: [os: :darwin, cpu: :aarch64],
            darwin_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_arm64: [os: :linux, cpu: :aarch64],
            windows_x86_64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp release_steps do
    if burrito_build?() do
      [:assemble, &Burrito.wrap/1]
    else
      [:assemble]
    end
  end

  # `mix tinfoil.build` sets BURRITO_TARGET and then calls the release task
  # in-process, but mix.exs is evaluated at Mix startup, before any task runs.
  # So the env var alone is never visible here and the task name has to be
  # checked too. See joshrotenberg/tinfoil#107.
  #
  #   mix tinfoil.build --target x  -> wrapped (CI and local)
  #   BURRITO_TARGET=x mix release  -> wrapped (raw Burrito flow)
  #   mix release                   -> plain (the Dockerfile and Fly image)
  defp burrito_build? do
    System.get_env("BURRITO_TARGET") != nil or
      match?(["tinfoil.build" | _], System.argv())
  end

  defp tinfoil do
    [
      targets: [
        :darwin_arm64,
        :darwin_x86_64,
        :linux_x86_64,
        :linux_arm64,
        :windows_x86_64
      ],
      single_runner_per_os: true,
      extra_artifacts: [
        "LICENSE",
        %{source: "README.md", dest: "share/doc/hexpm_mcp/README.md"}
      ],
      installer: [enabled: true],
      # homebrew and scoop stay off until this repo has a tap-push credential.
      # Enabling them is one block each here plus a COMMITTER_TOKEN secret.
      #
      # Pinned rather than inferred. Tinfoil's autodetection reads elixir from
      # the `~> 1.17` floor (this project builds on 1.19) and otp from whichever
      # runtime ran the generator, which produced the impossible pair 1.17/29.
      # Its zig inference is also broken and always yields the fallback. See
      # joshrotenberg/tinfoil#105 and #106.
      #
      # elixir and otp match ci.yml and the Dockerfile. zig 0.15.2 is what
      # burrito 1.5.x requires; it moves to 0.16.0 in 1.6.0, which we cannot
      # take yet (see the :burrito dep note above).
      ci: [
        elixir_version: "1.19",
        otp_version: "28",
        zig_version: "0.15.2"
      ]
    ]
  end
end
