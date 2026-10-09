#include "desktop_integration.h"

#include <shlobj.h>

#include <string>

namespace {

// Where the answer lives. Shared with the installer
// (packaging/windows/installer.iss), which writes "yes" or "no" according to
// its "Open .meow files" checkbox.
constexpr wchar_t kChoiceKey[] = L"Software\\MeowChess";
constexpr wchar_t kChoiceValue[] = L"FileAssociationChoice";

constexpr wchar_t kProgId[] = L"MeowChess.Tournament";
constexpr wchar_t kProgIdKey[] = L"Software\\Classes\\MeowChess.Tournament";
constexpr wchar_t kExtensionKey[] = L"Software\\Classes\\.meow";
constexpr wchar_t kApplicationKey[] =
    L"Software\\Classes\\Applications\\meow_chess.exe";

void SetString(const std::wstring& subkey, const wchar_t* value_name,
               const std::wstring& data) {
  ::RegSetKeyValueW(HKEY_CURRENT_USER, subkey.c_str(), value_name, REG_SZ,
                    data.c_str(),
                    static_cast<DWORD>((data.size() + 1) * sizeof(wchar_t)));
}

std::wstring ReadChoice() {
  wchar_t buffer[16] = {};
  DWORD size = sizeof(buffer);
  LSTATUS status =
      ::RegGetValueW(HKEY_CURRENT_USER, kChoiceKey, kChoiceValue,
                     RRF_RT_REG_SZ, nullptr, buffer, &size);
  return status == ERROR_SUCCESS ? std::wstring(buffer) : std::wstring();
}

void WriteChoice(const wchar_t* choice) {
  SetString(kChoiceKey, kChoiceValue, choice);
}

// Registers this executable as the .meow handler under the user's hive: a
// ProgID for the type, a place in the "Open with" list, and the extension's
// default. .meow is ours, so unlike a shared type there is no other owner to
// defer to; Windows still keeps a default the user picked themselves
// (UserChoice) ahead of all of this.
void RegisterMeowAssociation() {
  // An install path past MAX_PATH would be silently truncated in a fixed
  // buffer, so grow it until the whole path fits.
  std::wstring exe(MAX_PATH, L'\0');
  for (;;) {
    DWORD length = ::GetModuleFileNameW(nullptr, &exe[0],
                                        static_cast<DWORD>(exe.size()));
    if (length == 0) return;
    if (length < exe.size()) {
      exe.resize(length);
      break;
    }
    if (exe.size() >= 32768) return;
    exe.resize(exe.size() * 2);
  }
  const std::wstring open_command = L"\"" + exe + L"\" \"%1\"";

  SetString(kProgIdKey, nullptr, L"Meow Chess tournament");
  SetString(std::wstring(kProgIdKey) + L"\\DefaultIcon", nullptr,
            L"\"" + exe + L"\",0");
  SetString(std::wstring(kProgIdKey) + L"\\shell\\open\\command", nullptr,
            open_command);

  SetString(kExtensionKey, nullptr, kProgId);
  SetString(std::wstring(kExtensionKey) + L"\\OpenWithProgids", kProgId, L"");

  SetString(kApplicationKey, L"FriendlyAppName", L"Meow Chess");
  SetString(std::wstring(kApplicationKey) + L"\\shell\\open\\command", nullptr,
            open_command);
  SetString(std::wstring(kApplicationKey) + L"\\SupportedTypes", L".meow",
            L"");

  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

}  // namespace

void DesktopIntegrationMaybeSetup(HWND parent_window) {
#ifdef _DEBUG
  return;
#else
  // MEOW_CHESS_DESKTOP_SETUP=1 answers yes and =0 no without asking, for
  // scripted installs.
  wchar_t preset[4] = {};
  if (::GetEnvironmentVariableW(L"MEOW_CHESS_DESKTOP_SETUP", preset, 4) > 0) {
    if (std::wstring(preset) == L"0") return;
    if (std::wstring(preset) == L"1") {
      WriteChoice(L"yes");
      RegisterMeowAssociation();
      return;
    }
  }

  const std::wstring choice = ReadChoice();
  if (choice == L"yes") {
    // Refreshed every launch so the registration survives moving the
    // unzipped folder.
    RegisterMeowAssociation();
    return;
  }
  if (choice == L"no") return;

  const int answer = ::MessageBoxW(
      parent_window,
      L"Open .meow tournament files with Meow Chess when you double-click "
      L"them?\n\n"
      L"This only changes settings for your account. You can change it later "
      L"in Settings > Apps > Default apps.",
      L"Set up Meow Chess",
      MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON1);
  if (answer == IDYES) {
    WriteChoice(L"yes");
    RegisterMeowAssociation();
  } else if (answer == IDNO) {
    WriteChoice(L"no");
  }
#endif
}
