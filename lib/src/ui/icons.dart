/// Icons and highlight groups for the `viworkspace` explorer.
class WorkspaceIcons {
  static const String workspace = '❖';
  static const String chevronCollapsed = '';
  static const String chevronExpanded = '';
  static const String folderClosed = '';
  static const String folderOpen = '';
  static const String defaultFile = '󰈙';

  static const Map<String, (String, String)> _nameMap = {
    // Git
    '.gitignore': ('', 'ViworkspaceIconGit'),
    '.gitattributes': ('', 'ViworkspaceIconGit'),
    '.gitmodules': ('', 'ViworkspaceIconGit'),
    '.gitkeep': ('', 'ViworkspaceIconGit'),

    // Docker / Containers
    'dockerfile': ('󰡨', 'ViworkspaceIconDocker'),
    'containerfile': ('󰡨', 'ViworkspaceIconDocker'),
    '.dockerignore': ('󰡨', 'ViworkspaceIconDocker'),
    'docker-compose.yml': ('󰡨', 'ViworkspaceIconDocker'),
    'docker-compose.yaml': ('󰡨', 'ViworkspaceIconDocker'),
    'compose.yml': ('󰡨', 'ViworkspaceIconDocker'),
    'compose.yaml': ('󰡨', 'ViworkspaceIconDocker'),

    // Build / Task Runners
    'makefile': ('', 'ViworkspaceIconBuild'),
    'gnumakefile': ('', 'ViworkspaceIconBuild'),
    'cmakelists.txt': ('', 'ViworkspaceIconBuild'),
    'justfile': ('', 'ViworkspaceIconBuild'),
    'rakefile': ('', 'ViworkspaceIconBuild'),
    'meson.build': ('', 'ViworkspaceIconBuild'),
    'build.gradle': ('', 'ViworkspaceIconBuild'),
    'build.gradle.kts': ('', 'ViworkspaceIconBuild'),
    'settings.gradle': ('', 'ViworkspaceIconBuild'),
    'settings.gradle.kts': ('', 'ViworkspaceIconBuild'),

    // Dotfile Configs & Environment
    '.env': ('', 'ViworkspaceIconConfig'),
    '.env.local': ('', 'ViworkspaceIconConfig'),
    '.env.development': ('', 'ViworkspaceIconConfig'),
    '.env.production': ('', 'ViworkspaceIconConfig'),
    '.env.test': ('', 'ViworkspaceIconConfig'),
    '.env.example': ('', 'ViworkspaceIconConfig'),
    '.editorconfig': ('', 'ViworkspaceIconConfig'),
    '.prettierrc': ('', 'ViworkspaceIconConfig'),
    '.eslintrc': ('', 'ViworkspaceIconConfig'),
    '.babelrc': ('', 'ViworkspaceIconConfig'),
    '.npmrc': ('', 'ViworkspaceIconConfig'),
    '.nvmrc': ('', 'ViworkspaceIconConfig'),
    '.luarc.json': ('', 'ViworkspaceIconConfig'),
    '.clang-format': ('', 'ViworkspaceIconConfig'),
    '.clang-tidy': ('', 'ViworkspaceIconConfig'),

    // Licenses
    'license': ('', 'ViworkspaceIconLicense'),
    'license.md': ('', 'ViworkspaceIconLicense'),
    'license.txt': ('', 'ViworkspaceIconLicense'),
    'copying': ('', 'ViworkspaceIconLicense'),
    'copying.md': ('', 'ViworkspaceIconLicense'),

    // Lockfiles
    'pubspec.lock': ('󰌾', 'ViworkspaceMuted'),
    'cargo.lock': ('󰌾', 'ViworkspaceMuted'),
    'package-lock.json': ('󰌾', 'ViworkspaceMuted'),
    'pnpm-lock.yaml': ('󰌾', 'ViworkspaceMuted'),
    'yarn.lock': ('󰌾', 'ViworkspaceMuted'),
    'gemfile.lock': ('󰌾', 'ViworkspaceMuted'),
    'poetry.lock': ('󰌾', 'ViworkspaceMuted'),
    'composer.lock': ('󰌾', 'ViworkspaceMuted'),
    'flake.lock': ('󰌾', 'ViworkspaceMuted'),
    'uv.lock': ('󰌾', 'ViworkspaceMuted'),
    'bun.lockb': ('󰌾', 'ViworkspaceMuted'),
    'bun.lock': ('󰌾', 'ViworkspaceMuted'),

    // Ecosystem Manifests
    'pubspec.yaml': ('', 'ViworkspaceIconDart'),
    'cargo.toml': ('', 'ViworkspaceIconRust'),
    'go.mod': ('', 'ViworkspaceIconGo'),
    'go.sum': ('', 'ViworkspaceIconGo'),
    'go.work': ('', 'ViworkspaceIconGo'),
    'gemfile': ('', 'ViworkspaceIconRuby'),
  };

  static const Map<String, (String, String)> _extMap = {
    // Web / Frontend
    'js': ('', 'ViworkspaceIconJs'),
    'mjs': ('', 'ViworkspaceIconJs'),
    'cjs': ('', 'ViworkspaceIconJs'),
    'jsx': ('', 'ViworkspaceIconWeb'),
    'ts': ('', 'ViworkspaceIconTs'),
    'mts': ('', 'ViworkspaceIconTs'),
    'cts': ('', 'ViworkspaceIconTs'),
    'tsx': ('', 'ViworkspaceIconWeb'),
    'html': ('', 'ViworkspaceIconHtml'),
    'htm': ('', 'ViworkspaceIconHtml'),
    'css': ('', 'ViworkspaceIconCss'),
    'scss': ('', 'ViworkspaceIconCss'),
    'sass': ('', 'ViworkspaceIconCss'),
    'less': ('', 'ViworkspaceIconCss'),
    'vue': ('󰡄', 'ViworkspaceIconWeb'),
    'svelte': ('', 'ViworkspaceIconWeb'),
    'astro': ('', 'ViworkspaceIconWeb'),
    'wasm': ('', 'ViworkspaceIconWeb'),
    'graphql': ('', 'ViworkspaceIconWeb'),
    'gql': ('', 'ViworkspaceIconWeb'),

    // Systems & Compiled
    'c': ('', 'ViworkspaceIconC'),
    'cpp': ('', 'ViworkspaceIconC'),
    'cc': ('', 'ViworkspaceIconC'),
    'cxx': ('', 'ViworkspaceIconC'),
    'c++': ('', 'ViworkspaceIconC'),
    'h': ('', 'ViworkspaceIconC'),
    'hh': ('', 'ViworkspaceIconC'),
    'hpp': ('', 'ViworkspaceIconC'),
    'hxx': ('', 'ViworkspaceIconC'),
    'rs': ('', 'ViworkspaceIconRust'),
    'go': ('', 'ViworkspaceIconGo'),
    'zig': ('', 'ViworkspaceIconC'),
    'nim': ('', 'ViworkspaceIconC'),
    'v': ('', 'ViworkspaceIconC'),
    'd': ('', 'ViworkspaceIconC'),
    'asm': ('', 'ViworkspaceIconC'),
    's': ('', 'ViworkspaceIconC'),
    'swift': ('', 'ViworkspaceIconC'),
    'm': ('', 'ViworkspaceIconC'),
    'mm': ('', 'ViworkspaceIconC'),
    'cs': ('󰌛', 'ViworkspaceIconC'),
    'csx': ('󰌛', 'ViworkspaceIconC'),
    'fs': ('', 'ViworkspaceIconC'),
    'fsx': ('', 'ViworkspaceIconC'),

    // JVM
    'java': ('', 'ViworkspaceIconJvm'),
    'jar': ('', 'ViworkspaceIconJvm'),
    'class': ('', 'ViworkspaceIconJvm'),
    'kt': ('', 'ViworkspaceIconJvm'),
    'kts': ('', 'ViworkspaceIconJvm'),
    'scala': ('', 'ViworkspaceIconJvm'),
    'sc': ('', 'ViworkspaceIconJvm'),
    'groovy': ('', 'ViworkspaceIconJvm'),
    'gradle': ('', 'ViworkspaceIconBuild'),
    'clj': ('', 'ViworkspaceIconJvm'),
    'cljs': ('', 'ViworkspaceIconJvm'),
    'cljc': ('', 'ViworkspaceIconJvm'),
    'edn': ('', 'ViworkspaceIconJvm'),

    // Scripting & Functional
    'dart': ('', 'ViworkspaceIconDart'),
    'py': ('', 'ViworkspaceIconPython'),
    'pyi': ('', 'ViworkspaceIconPython'),
    'pyw': ('', 'ViworkspaceIconPython'),
    'ipynb': ('', 'ViworkspaceIconPython'),
    'rb': ('', 'ViworkspaceIconRuby'),
    'erb': ('', 'ViworkspaceIconRuby'),
    'gemspec': ('', 'ViworkspaceIconRuby'),
    'php': ('', 'ViworkspaceIconWeb'),
    'pl': ('', 'ViworkspaceIconShell'),
    'pm': ('', 'ViworkspaceIconShell'),
    'lua': ('', 'ViworkspaceIconLua'),
    'r': ('󰟔', 'ViworkspaceIconData'),
    'rmd': ('󰟔', 'ViworkspaceIconData'),
    'jl': ('', 'ViworkspaceIconData'),
    'ex': ('', 'ViworkspaceIconRuby'),
    'exs': ('', 'ViworkspaceIconRuby'),
    'eex': ('', 'ViworkspaceIconRuby'),
    'heex': ('', 'ViworkspaceIconRuby'),
    'erl': ('', 'ViworkspaceIconRuby'),
    'hrl': ('', 'ViworkspaceIconRuby'),
    'hs': ('', 'ViworkspaceIconLua'),
    'lhs': ('', 'ViworkspaceIconLua'),
    'ml': ('', 'ViworkspaceIconLua'),
    'mli': ('', 'ViworkspaceIconLua'),
    'vim': ('', 'ViworkspaceIconShell'),

    // Shell & Terminal
    'sh': ('', 'ViworkspaceIconShell'),
    'zsh': ('', 'ViworkspaceIconShell'),
    'bash': ('', 'ViworkspaceIconShell'),
    'fish': ('', 'ViworkspaceIconShell'),
    'ksh': ('', 'ViworkspaceIconShell'),
    'csh': ('', 'ViworkspaceIconShell'),
    'awk': ('', 'ViworkspaceIconShell'),
    'sed': ('', 'ViworkspaceIconShell'),
    'ps1': ('󰨊', 'ViworkspaceIconShell'),
    'psm1': ('󰨊', 'ViworkspaceIconShell'),
    'psd1': ('󰨊', 'ViworkspaceIconShell'),
    'bat': ('', 'ViworkspaceIconShell'),
    'cmd': ('', 'ViworkspaceIconShell'),

    // Config, Data, Cloud & DB
    'json': ('', 'ViworkspaceIconConfig'),
    'jsonc': ('', 'ViworkspaceIconConfig'),
    'json5': ('', 'ViworkspaceIconConfig'),
    'jsonl': ('', 'ViworkspaceIconConfig'),
    'proto': ('', 'ViworkspaceIconConfig'),
    'yaml': ('', 'ViworkspaceIconConfig'),
    'yml': ('', 'ViworkspaceIconConfig'),
    'toml': ('', 'ViworkspaceIconConfig'),
    'xml': ('󰗀', 'ViworkspaceIconConfig'),
    'plist': ('󰗀', 'ViworkspaceIconConfig'),
    'xul': ('󰗀', 'ViworkspaceIconConfig'),
    'csproj': ('󰗀', 'ViworkspaceIconConfig'),
    'sln': ('󰗀', 'ViworkspaceIconConfig'),
    'ini': ('', 'ViworkspaceIconConfig'),
    'cfg': ('', 'ViworkspaceIconConfig'),
    'conf': ('', 'ViworkspaceIconConfig'),
    'properties': ('', 'ViworkspaceIconConfig'),
    'env': ('', 'ViworkspaceIconConfig'),
    'csv': ('', 'ViworkspaceIconData'),
    'tsv': ('', 'ViworkspaceIconData'),
    'sql': ('', 'ViworkspaceIconData'),
    'sqlite': ('', 'ViworkspaceIconData'),
    'db': ('', 'ViworkspaceIconData'),
    'prisma': ('', 'ViworkspaceIconData'),
    'nix': ('', 'ViworkspaceIconConfig'),
    'tf': ('', 'ViworkspaceIconConfig'),
    'tfvars': ('', 'ViworkspaceIconConfig'),
    'hcl': ('', 'ViworkspaceIconConfig'),
    'dockerfile': ('󰡨', 'ViworkspaceIconDocker'),
    'cmake': ('', 'ViworkspaceIconBuild'),

    // Documentation & Office
    'md': ('', 'ViworkspaceIconMarkdown'),
    'mdx': ('', 'ViworkspaceIconMarkdown'),
    'markdown': ('', 'ViworkspaceIconMarkdown'),
    'txt': ('󰈙', 'ViworkspaceIconDocs'),
    'text': ('󰈙', 'ViworkspaceIconDocs'),
    'rst': ('󰈙', 'ViworkspaceIconDocs'),
    'org': ('󰈙', 'ViworkspaceIconDocs'),
    'adoc': ('󰈙', 'ViworkspaceIconDocs'),
    'asciidoc': ('󰈙', 'ViworkspaceIconDocs'),
    'tex': ('', 'ViworkspaceIconDocs'),
    'bib': ('', 'ViworkspaceIconDocs'),
    'cls': ('', 'ViworkspaceIconDocs'),
    'sty': ('', 'ViworkspaceIconDocs'),
    'pdf': ('', 'ViworkspaceIconDocs'),
    'epub': ('', 'ViworkspaceIconDocs'),
    'doc': ('󰈬', 'ViworkspaceIconDocs'),
    'docx': ('󰈬', 'ViworkspaceIconDocs'),
    'rtf': ('󰈬', 'ViworkspaceIconDocs'),
    'xls': ('󰈛', 'ViworkspaceIconDocs'),
    'xlsx': ('󰈛', 'ViworkspaceIconDocs'),
    'ppt': ('󰈧', 'ViworkspaceIconDocs'),
    'pptx': ('󰈧', 'ViworkspaceIconDocs'),
    'log': ('', 'ViworkspaceMuted'),

    // Media & Fonts
    'png': ('', 'ViworkspaceIconMedia'),
    'jpg': ('', 'ViworkspaceIconMedia'),
    'jpeg': ('', 'ViworkspaceIconMedia'),
    'gif': ('', 'ViworkspaceIconMedia'),
    'webp': ('', 'ViworkspaceIconMedia'),
    'bmp': ('', 'ViworkspaceIconMedia'),
    'ico': ('', 'ViworkspaceIconMedia'),
    'tiff': ('', 'ViworkspaceIconMedia'),
    'heic': ('', 'ViworkspaceIconMedia'),
    'avif': ('', 'ViworkspaceIconMedia'),
    'svg': ('󰜡', 'ViworkspaceIconMedia'),
    'mp3': ('', 'ViworkspaceIconMedia'),
    'wav': ('', 'ViworkspaceIconMedia'),
    'flac': ('', 'ViworkspaceIconMedia'),
    'ogg': ('', 'ViworkspaceIconMedia'),
    'm4a': ('', 'ViworkspaceIconMedia'),
    'aac': ('', 'ViworkspaceIconMedia'),
    'mp4': ('', 'ViworkspaceIconMedia'),
    'mkv': ('', 'ViworkspaceIconMedia'),
    'mov': ('', 'ViworkspaceIconMedia'),
    'webm': ('', 'ViworkspaceIconMedia'),
    'avi': ('', 'ViworkspaceIconMedia'),
    'ttf': ('', 'ViworkspaceIconMedia'),
    'otf': ('', 'ViworkspaceIconMedia'),
    'woff': ('', 'ViworkspaceIconMedia'),
    'woff2': ('', 'ViworkspaceIconMedia'),
    'eot': ('', 'ViworkspaceIconMedia'),

    // Archives
    'zip': ('', 'ViworkspaceIconArchive'),
    'tar': ('', 'ViworkspaceIconArchive'),
    'gz': ('', 'ViworkspaceIconArchive'),
    'tgz': ('', 'ViworkspaceIconArchive'),
    'bz2': ('', 'ViworkspaceIconArchive'),
    'xz': ('', 'ViworkspaceIconArchive'),
    'zst': ('', 'ViworkspaceIconArchive'),
    '7z': ('', 'ViworkspaceIconArchive'),
    'rar': ('', 'ViworkspaceIconArchive'),
    'dmg': ('', 'ViworkspaceIconArchive'),
    'iso': ('', 'ViworkspaceIconArchive'),

    // Locks, Security, Binaries & Diffs
    'lock': ('󰌾', 'ViworkspaceMuted'),
    'pem': ('󰌆', 'ViworkspaceIconSecurity'),
    'crt': ('󰌆', 'ViworkspaceIconSecurity'),
    'cer': ('󰌆', 'ViworkspaceIconSecurity'),
    'key': ('󰌆', 'ViworkspaceIconSecurity'),
    'pub': ('󰌆', 'ViworkspaceIconSecurity'),
    'gpg': ('󰌆', 'ViworkspaceIconSecurity'),
    'asc': ('󰌆', 'ViworkspaceIconSecurity'),
    'exe': ('', 'ViworkspaceIconBinary'),
    'dll': ('', 'ViworkspaceIconBinary'),
    'so': ('', 'ViworkspaceIconBinary'),
    'dylib': ('', 'ViworkspaceIconBinary'),
    'bin': ('', 'ViworkspaceIconBinary'),
    'o': ('', 'ViworkspaceIconBinary'),
    'a': ('', 'ViworkspaceIconBinary'),
    'out': ('', 'ViworkspaceIconBinary'),
    'diff': ('', 'ViworkspaceIconGit'),
    'patch': ('', 'ViworkspaceIconGit'),
  };

  /// Returns `(icon, highlightGroup)` for a given [fileName].
  static (String, String) iconForFile(String fileName) {
    final lowerName = fileName.toLowerCase();
    final exactMatch = _nameMap[lowerName];
    if (exactMatch != null) return exactMatch;

    if (lowerName.startsWith('.env.')) {
      return ('', 'ViworkspaceIconConfig');
    }

    final dotIdx = lowerName.lastIndexOf('.');
    if (dotIdx > 0 && dotIdx < lowerName.length - 1) {
      final ext = lowerName.substring(dotIdx + 1);
      final match = _extMap[ext];
      if (match != null) return match;
    }
    return (defaultFile, 'ViworkspaceIconDefault');
  }
}
