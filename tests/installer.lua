-- autovim — installer distro-detection + dependency-routing suite
--
-- Run headless:
--   nvim --headless -u NONE -l tests/installer.lua
--
-- WHY THIS SUITE EXISTS. install.sh used to recognise distros by `ID` alone,
-- naming three Arch derivatives and three Debian ones. Every other respin —
-- CachyOS, Garuda, Nobara, Zorin, elementary, KDE neon, openSUSE at all —
-- fell through to "Automatic dep install isn't supported on this system",
-- which is what a user hit on an Arch-family laptop whose ID is not the
-- literal string `arch`. The bug is a one-line `case` pattern, and nothing in
-- the repo could observe it: the installer is a shell script that runs once,
-- on a machine that is by definition the only distro the author tested.
--
-- So the assertions below drive the REAL `detect_os` out of the REAL
-- install.sh against fixture `/etc/os-release` files, one per distro AutoVim
-- claims to support. A fixture costs nothing and covers a platform no CI
-- runner here has. `uname` is stubbed to report Linux so the Linux branch is
-- exercised when the suite runs on macOS too — otherwise half the matrix
-- silently reports `macos` and passes.
--
-- Per the family runner contract (shared/conventions/lua-nvim-plugin-development.md):
-- `-u NONE -l`, a printed `<P> passed, <F> failed` summary, explicit exit.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local pass_count, fail_count = 0, 0
local function ok(name, cond, detail)
  if cond then
    pass_count = pass_count + 1
    io.stdout:write("  ok   " .. name .. "\n")
  else
    fail_count = fail_count + 1
    io.stdout:write("  FAIL " .. name)
    if detail ~= nil then io.stdout:write("  (" .. tostring(detail) .. ")") end
    io.stdout:write("\n")
  end
end

local function write(path, body)
  local fh = assert(io.open(path, "w"))
  fh:write(body)
  fh:close()
end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/bin", "p")
vim.fn.mkdir(tmp .. "/osr", "p")

-- The uname stub. Only `-s` is answered; anything else defers to the real
-- binary so an unrelated call cannot be silently corrupted by the stub.
write(tmp .. "/bin/uname", [[#!/bin/sh
if [ "$1" = "-s" ]; then echo Linux; exit 0; fi
for d in /usr/bin /bin /usr/local/bin; do
  [ -x "$d/uname" ] && exec "$d/uname" "$@"
done
echo Linux
]])
os.execute("chmod +x " .. vim.fn.shellescape(tmp .. "/bin/uname"))

-- sh_query sources install.sh for its functions only (AUTOVIM_LIB_ONLY=1) and
-- evaluates one expression. Sourcing is what makes this a test of the shipped
-- code rather than of a copy of its logic.
local function sh_query(expr, env)
  local prefix = ""
  for k, v in pairs(env or {}) do
    prefix = prefix .. k .. "=" .. vim.fn.shellescape(v) .. " "
  end
  local cmd = ("cd %s && PATH=%s:$PATH %sAUTOVIM_LIB_ONLY=1 bash -c '. ./install.sh; %s' 2>&1"):format(
    vim.fn.shellescape(root), vim.fn.shellescape(tmp .. "/bin"), prefix, expr)
  local out = vim.fn.system(cmd)
  return (out:gsub("%s+$", ""))
end

io.stdout:write("\n[0] the suite is driving the real install.sh\n")
--
-- A sourcing failure would make every detect_os call below return the empty
-- string, and "" never equals an expected distro — so the whole matrix would
-- fail loudly rather than silently pass. This asserts the positive case
-- anyway, so a green run means the functions were genuinely loaded.
ok("install.sh sources cleanly with AUTOVIM_LIB_ONLY=1",
  sh_query("echo LOADED:$?") == "LOADED:0", sh_query("echo LOADED:$?"))
ok("sourcing it does NOT run an install",
  not sh_query("echo done"):find("AutoVim installer", 1, true),
  "main() ran while the file was merely sourced")
ok("the uname stub is in effect",
  sh_query("uname -s") == "Linux", sh_query("uname -s"))

io.stdout:write("\n[1] distro identity resolves through ID, then ID_LIKE\n")
--
-- Each fixture is the real shape of that distro's /etc/os-release, trimmed to
-- the two fields the mapping reads. The `want` column is the package-manager
-- family AutoVim must choose.
local cases = {
  -- Arch and friends. Only the first has ID=arch; the rest are the ones the
  -- old ID-only match could not see.
  { "arch",         'ID=arch\n',                                        "arch"   },
  { "manjaro",      'ID=manjaro\nID_LIKE=arch\n',                       "arch"   },
  { "endeavouros",  'ID=endeavouros\nID_LIKE=arch\n',                   "arch"   },
  { "cachyos",      'ID=cachyos\nID_LIKE=arch\n',                       "arch"   },
  { "garuda",       'ID=garuda\nID_LIKE=arch\n',                        "arch"   },
  { "arcolinux",    'ID=arcolinux\nID_LIKE=arch\n',                     "arch"   },
  -- Debian, Ubuntu and the Ubuntu respins.
  { "debian",       'ID=debian\n',                                      "debian" },
  { "ubuntu",       'ID=ubuntu\nID_LIKE=debian\n',                      "debian" },
  { "pop",          'ID=pop\nID_LIKE="ubuntu debian"\n',                "debian" },
  { "linuxmint",    'ID=linuxmint\nID_LIKE="ubuntu debian"\n',          "debian" },
  { "zorin",        'ID=zorin\nID_LIKE="ubuntu debian"\n',              "debian" },
  { "elementary",   'ID=elementary\nID_LIKE="ubuntu debian"\n',         "debian" },
  { "neon",         'ID=neon\nID_LIKE="ubuntu debian"\n',               "debian" },
  { "raspbian",     'ID=raspbian\nID_LIKE=debian\n',                    "debian" },
  -- Fedora and the RHEL rebuilds.
  { "fedora",       'ID=fedora\n',                                      "fedora" },
  { "nobara",       'ID=nobara\nID_LIKE=fedora\n',                      "fedora" },
  { "rocky",        'ID="rocky"\nID_LIKE="rhel centos fedora"\n',       "fedora" },
  { "almalinux",    'ID="almalinux"\nID_LIKE="rhel centos fedora"\n',   "fedora" },
  -- openSUSE, which the installer could not handle at all before this change.
  { "tumbleweed",   'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n', "suse" },
  { "leap",         'ID="opensuse-leap"\nID_LIKE="suse opensuse"\n',    "suse"   },
  { "sles",         'ID="sles"\nID_LIKE="sle suse"\n',                  "suse"   },
}
for _, c in ipairs(cases) do
  local name, body, want = c[1], c[2], c[3]
  local path = tmp .. "/osr/" .. name
  write(path, body)
  local got = sh_query("detect_os", { AUTOVIM_OS_RELEASE = path })
  ok(("%-12s → %s"):format(name, want), got == want, "got " .. got)
end

io.stdout:write("\n[2] an unknown distro is reported as unknown, not guessed\n")
--
-- The fallback must stay honest. Mapping an unrecognised ID onto a family
-- would run some other distro's package manager, and the failure mode of
-- `pacman` on a Void box is worse than an accurate refusal.
write(tmp .. "/osr/void", 'ID=void\n')
ok("void (no ID_LIKE) → linux-other",
  sh_query("detect_os", { AUTOVIM_OS_RELEASE = tmp .. "/osr/void" }) == "linux-other")
write(tmp .. "/osr/exotic", 'ID=plan9\nID_LIKE="inferno"\n')
ok("an unrelated ID_LIKE → linux-other",
  sh_query("detect_os", { AUTOVIM_OS_RELEASE = tmp .. "/osr/exotic" }) == "linux-other")
ok("a missing os-release → linux-other",
  sh_query("detect_os", { AUTOVIM_OS_RELEASE = tmp .. "/osr/does-not-exist" }) == "linux-other")

io.stdout:write("\n[3] linux-other refuses with instructions, and names the floor\n")
--
-- The refusal is the one path a user READS, and it has to tell them what to
-- install. It also must not claim a version the rest of the script does not
-- enforce.
local refusal = sh_query('install_deps linux-other || true', {})
ok("linux-other refuses rather than running a package manager",
  refusal:find("Could not identify", 1, true) ~= nil, refusal)
ok("the refusal lists the dependencies by name",
  refusal:find("ripgrep", 1, true) and refusal:find("pandoc", 1, true) ~= nil)
ok("the refusal quotes the real neovim floor",
  refusal:find("0.11.2", 1, true) ~= nil)
ok("the refusal names the escape hatch",
  refusal:find("AUTOVIM_SKIP_DEPS=1", 1, true) ~= nil)

io.stdout:write("\n[4] package names are per-family, not copied from one distro\n")
--
-- These are the names that actually differ between families. Getting one
-- wrong fails the install at the package manager, late, with the distro's
-- error rather than ours.
local pkg = {
  { "fd",  "arch",   "fd"              },
  { "fd",  "debian", "fd-find"         },
  { "fd",  "fedora", "fd-find"         },
  { "fd",  "suse",   "fd"              },
  { "go",  "arch",   "go"              },
  { "go",  "debian", "golang-go"       },
  { "go",  "fedora", "golang"          },
  { "go",  "suse",   "go"              },
  { "cc",  "arch",   "gcc"             },
  { "cc",  "debian", "build-essential" },
  { "cc",  "fedora", "gcc"             },
  { "cc",  "suse",   "gcc"             },
  { "cc",  "macos",  ""                },
  { "ripgrep", "suse", "ripgrep"       },
}
for _, p in ipairs(pkg) do
  local tool, os_, want = p[1], p[2], p[3]
  local got = sh_query(("pkg_name %s %s"):format(tool, os_))
  ok(("pkg_name %-8s %-7s → %q"):format(tool, os_, want), got == want, "got " .. ("%q"):format(got))
end

io.stdout:write("\n[5] every supported family has a package manager wired up\n")
--
-- A family that detect_os can RETURN but pm_install cannot act on is the
-- original bug wearing a different hat: detection succeeds and the install
-- dies later. This asserts the two tables agree.
for _, os_ in ipairs({ "macos", "arch", "debian", "fedora", "suse" }) do
  local body = sh_query(('type pm_install | grep -c "%s)"'):format(os_))
  ok(("pm_install handles %s"):format(os_), tonumber(body) and tonumber(body) >= 1, body)
end

io.stdout:write("\n[5a] Arch-family package installs never run a system upgrade\n")
-- Drive the real pm_install through a fake sudo, so the test observes the
-- command that would run without touching the host package manager. Every
-- Arch derivative above resolves to this same 'arch' branch.
local arch_install = sh_query([[sudo() { printf "sudo %s\n" "$*"; }; pm_install arch neovim go]])
ok("Arch installs only the requested packages",
  arch_install:find("sudo pacman -S --needed --noconfirm neovim go", 1, true) ~= nil,
  arch_install)
ok("Arch install does not refresh or upgrade the system",
  arch_install:find("pacman -Syu", 1, true) == nil
    and arch_install:find("pacman -Sy", 1, true) == nil
    and arch_install:find("--sysupgrade", 1, true) == nil
    and arch_install:find("--refresh", 1, true) == nil,
  arch_install)

io.stdout:write("\n[6] the mise / package-manager split is coherent\n")
--
-- The contract: mise is preferred for the tools it genuinely carries, and the
-- system set always comes from the distro. A tool in both lists would be
-- installed twice; a system tool in the mise list would be looked up in a
-- registry that has no entry for it and fall back on every single run.
local dev = vim.split(sh_query("echo $DEV_TOOLS"), "%s+")
local sys = vim.split(sh_query("echo $SYS_TOOLS"), "%s+")
local in_dev = {}
for _, t in ipairs(dev) do in_dev[t] = true end
local overlap = {}
for _, t in ipairs(sys) do if in_dev[t] then overlap[#overlap + 1] = t end end
ok("DEV_TOOLS and SYS_TOOLS are disjoint", #overlap == 0, table.concat(overlap, ","))
ok("the tools AutoVim actually needs are all covered",
  #dev + #sys >= 11, ("%d dev + %d sys"):format(#dev, #sys))
for _, t in ipairs({ "neovim", "ripgrep", "fd", "fzf", "go", "pandoc" }) do
  ok(("%s is a mise-preferred tool"):format(t), in_dev[t] == true)
end
local in_sys = {}
for _, t in ipairs(sys) do in_sys[t] = true end
for _, t in ipairs({ "git", "cc", "curl", "rsync" }) do
  -- These have no mise registry entry; asking mise for them would fail on
  -- every run and fall back, which is just a slower package install.
  ok(("%s comes from the system, not mise"):format(t), in_sys[t] == true)
end

io.stdout:write("\n[7] AUTOVIM_NO_MISE is honoured\n")
--
-- The opt-out has to be checked BEFORE `command -v mise`, or a box with mise
-- installed ignores the flag.
ok("mise_usable is false when AUTOVIM_NO_MISE=1",
  sh_query("mise_usable && echo yes || echo no", { AUTOVIM_NO_MISE = "1" }) == "no")

io.stdout:write("\n[8] the neovim floor is declared once and enforced everywhere\n")
--
-- smoke.lua pins the same constant from the other side (README agreement).
-- What it could not see is WHERE the gate runs: until this change the check
-- lived inside the Debian branch, so an openSUSE Leap box with an ancient
-- neovim installed cleanly and then could not start. ensure_nvim is the
-- universal gate and main() must call it for every OS, not inside a case.
local src = table.concat(vim.fn.readfile(root .. "/install.sh"), "\n")
ok("NVIM_MIN is declared once as a constant",
  src:match('NVIM_MIN="([%d%.]+)"') == "0.11.2", tostring(src:match('NVIM_MIN="([%d%.]+)"')))
ok("ensure_nvim exists", src:find("ensure_nvim()", 1, true) ~= nil)
ok("main() calls ensure_nvim unconditionally, not per-distro",
  src:find("install_deps \"$os\"\n    ensure_nvim \"$os\"", 1, true) ~= nil)
ok("the gate compares against the constant, not a literal",
  src:find('version_ge "$v" "$NVIM_MIN"', 1, true) ~= nil)
ok("no bare 0.10 floor survives anywhere",
  src:match('version_ge "%$v" "0%.10') == nil)

io.stdout:write("\n[9] the script stays runnable by macOS's bash 3.2\n")
--
-- `curl … | bash` on macOS resolves /bin/bash, which is 3.2 and has no
-- associative arrays. The package tables here are case statements for that
-- reason, and a future edit reaching for `declare -A` would break every mac
-- install while passing on Linux.
--
-- SCANNED WITH THE COMMENTS STRIPPED, and that is not a detail. The header
-- of install.sh NAMES these three constructs in order to forbid them, so a
-- search over the raw text matches its own documentation and the assertion
-- passes for the wrong reason -- or, as it did on the first run here, fails
-- for the wrong reason. A ban has to be checked against code.
local code = {}
for _, line in ipairs(vim.fn.readfile(root .. "/install.sh")) do
  if not line:match("^%s*#") then code[#code + 1] = line end
end
code = table.concat(code, "\n")
ok("the comment-stripped source still has the script in it",
  code:find("detect_os()", 1, true) ~= nil and #code > 2000, #code)
ok("the strip removed the header that names the banned constructs",
  code:find("must not use associative arrays", 1, true) == nil)
ok("no associative arrays", code:find("declare %-A") == nil)
ok("no mapfile/readarray", code:find("mapfile") == nil and code:find("readarray") == nil)
ok("no ${var^^} case expansion", code:find("%${%w+%^%^}") == nil)
ok("bash -n accepts the script",
  vim.fn.system("bash -n " .. vim.fn.shellescape(root .. "/install.sh") .. " 2>&1") == "" )

-- A floor, so a section that stops contributing assertions is visible as a
-- failure rather than as a shorter green run.
local MIN_ASSERTIONS = 60
do
  local ran = pass_count + fail_count
  ok(("assertion floor: ran %d, expected at least %d"):format(ran, MIN_ASSERTIONS),
    ran >= MIN_ASSERTIONS, "a section stopped contributing assertions")
end

io.stdout:write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)
