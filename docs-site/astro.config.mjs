// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

// Static output only. The build runs inside a Nix derivation with no network
// and no server, and nginx serves dist/ straight from the store.
export default defineConfig({
  site: "https://docs.ericsharma.xyz",
  build: { format: "directory" },
  // No sharp. Nothing on this site is a raster image that needs processing —
  // the logo is an SVG — and the default sharp service would pull
  // platform-specific prebuilt binaries into the Nix build.
  image: { service: { entrypoint: "astro/assets/services/noop" } },
  integrations: [
    starlight({
      title: "Nix of Time",
      description:
        "Documentation for a two-machine, ~30-service NixOS homelab. Declarative, self-hosted, and written next to the code it describes.",
      tagline: "A growing fleet of machines. One declarative source of truth.",
      logo: { src: "./src/assets/logo.svg", replacesTitle: false },
      customCss: ["./src/styles/theme.css"],
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/ericsharma/nix-of-time",
        },
      ],
      // The repo's markdown is the source of truth and is synced in by
      // scripts/sync-docs.mjs, so per-page "edit this page" links would point
      // at generated files. Pages set editUrl: false individually.
      editLink: {},
      lastUpdated: false,
      pagination: true,
      tableOfContents: { minHeadingLevel: 2, maxHeadingLevel: 3 },
      sidebar: [
        {
          label: "The Fleet",
          items: [
            { slug: "architecture" },
            { slug: "fleet/trigkey" },
            { slug: "fleet/gmktec" },
            { slug: "fleet/docker-services" },
            { slug: "adding-a-machine" },
          ],
        },
        {
          label: "Media",
          items: [
            { slug: "media" },
            { slug: "media/guitar-library" },
            { slug: "services/usenet", label: "Arr stack & Usenet" },
            { slug: "media/eternatv" },
            { slug: "media/jellyfin" },
            { slug: "media/garage" },
          ],
        },
        {
          label: "Services",
          autogenerate: { directory: "services" },
        },
        {
          label: "Operations",
          items: [
            { slug: "adding-a-service" },
            { slug: "secrets" },
            { slug: "networking" },
            { slug: "claude-skills" },
          ],
        },
        {
          label: "Reference",
          items: [
            { slug: "reference/repo-conventions" },
            { slug: "reference/repo-readme" },
          ],
        },
      ],
    }),
  ],
});
