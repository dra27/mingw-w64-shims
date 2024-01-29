/* ************************************************************************** *
 * Copyright 2024 David Allsopp Ltd.                                          *
 *                                                                            *
 * Permission to use, copy, modify, and/or distribute this software for any   *
 * purpose with or without fee is hereby granted, provided that the above     *
 * copyright notice and this permission notice appear in all copies.          *
 *                                                                            *
 * The SOFTWARE is provided "as is" and the AUTHOR disclaims all warranties   *
 * with regard to this SOFTWARE including all implied warranties of           *
 * merchantability and fitness. In no event shall the AUTHOR be liable for    *
 * any special, direct, indirect, or consequential damages or any damages     *
 * whatsoever resulting from loss of use, data or profits, whether in an      *
 * action of contract, negligence or other tortious action, arising out of or *
 * in connection with the use or performance of this SOFTWARE.                *
 * ************************************************************************** */

#include <windows.h>

/* CYGWIN_ROOT should be passed on the command line. Escaping this constant is,
   especially when UCS-2 is taken into account, something of a command-line
   nightmare, so we turn to the preprocessor for some limited aid.

   If compiled with, say, '-DCYGWIN_ROOT=C:\cygwin64', this macro dance will
   result in definitions of CYGWIN_PATH and CYGWIN_DIR semantically equivalent
   to:

   #define CYGWIN_PATH L"\"C:\\cygwin64\"bin;"
   #define CYGWIN_DIR L"\"C:\\cygwin64\"bin\\"

   This is the best that can be done with the C preprocessor - by stringifying
   the constant twice, any embedded backslashes or non-printing/extended
   characters are appropriately preserved, at the cost of CYGWIN_ROOT gaining
   an outer set of double-quotes. Given that the strings are copied to fresh
   buffers anyhow, the pointers and the second double-quote character are
   adjusted later. */
#define QUOTE3(x) L ## #x
#define QUOTE2(x) QUOTE3(#x)
#define QUOTE(x) QUOTE2(x)

#define CYGWIN_PATH QUOTE(CYGWIN_ROOT) L"bin;"
#define CYGWIN_DIR QUOTE(CYGWIN_ROOT) L"bin\\"

/* Executable entry point. This program is compiled without the CRT in order to
   considerably reduce the executable size. */
void shim(void) {
  LPWSTR cygwin_path = CYGWIN_PATH;
  LPWSTR cygwin_dir = CYGWIN_DIR;

  /* cygwin_path and cygwin_dir have one extra double-quote character at the
     start */
  cygwin_path++;
  cygwin_dir++;

  DWORD prefix_len = lstrlenW(cygwin_path);

  /* If the code jumps to exit_process, the program exits with error */
  DWORD exitcode = 1;

  /* 1. Read current value of PATH and prepend it with cygwin_path */

  DWORD size = 8192;
  DWORD ret;
  LPWSTR current_path =
    HeapAlloc(GetProcessHeap(), 0, (size + prefix_len) * sizeof(WCHAR));

  /* Copy cygwin_path to the start of current_path */
  if (!current_path ||
      !lstrcpynW(current_path, cygwin_path, prefix_len + 1))
    goto exit_process;
  /* Correct the stray double-quote from the preprocessor */
  current_path[prefix_len - 5] = L'\\';

  /* Write the current value of PATH _after_ cygwin_path */
  while (current_path != NULL &&
         (ret = GetEnvironmentVariableW(L"PATH",
                                        current_path + prefix_len,
                                        size)) > size) {
    size = ret;
    current_path =
      HeapReAlloc(GetProcessHeap(), 0, current_path, size + prefix_len);
  }

  /* Store the resulting value back to PATH. Note that we could check at this
     point that the prefix wasn't already there, but this seems unnecessary,
     as long as the shims are being used logically. If a shim came first in
     PATH, once the shim'd executable runs, it will now have the cygwin_path
     at the front of PATH, so should not see any further shims. Hopefully that
     logic passes the test of time and no exploding environments. */
  if (!current_path || !SetEnvironmentVariableW(L"PATH", current_path))
    goto exit_process;

  /* 2. Compute the image which is going to be executed */

  /* First get our basename */
  size = MAX_PATH + 1;
  LPWSTR module_name = HeapAlloc(GetProcessHeap(), 0, size * sizeof(WCHAR));

  /* GetModuleFileNameW only indicates that the buffer wasn't big enough, it
     doesn't return the size. */
  while (module_name != NULL &&
         size < 0x100000 &&
         GetModuleFileNameW(NULL, module_name, size) != 0 &&
         GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
    size += 8192;
    module_name =
      HeapReAlloc(GetProcessHeap(), 0, module_name, size);
  }

  int len;
  /* GetLastError() refers to the most recent call to GetModuleFileNameW */
  if (!module_name ||
      GetLastError() != ERROR_SUCCESS ||
      (len = lstrlenW(module_name)) < 1)
    goto exit_process;

  /* Wind back either to the start of the string, or to the first slash,
     backslash or colon (rather than needing another complete buffer for
     GetFullPathNameW). */
  int module_basename_len = 0;
  LPWSTR module_basename = module_name + len - 1;
  while (module_basename >= module_name &&
         *module_basename != '\\' &&
         *module_basename != '/' &&
         *module_basename != ':') {
    module_basename_len++;
    module_basename--;
  }
  /* module_basename either points to the separator or to the character _before_
     module_name, so wind it forwards one byte. */
  module_basename++;
  /* module_basename_len is now lstrlenW(module_basename) */

  /* Now construct the actual image we're going to run. NB Although PATH now
     includes the required root, we don't know that the shim has been named
     to an executable which actually exists, so don't rely on a PATH search
     (or an unnecessary stat from here). */
  int image_len = prefix_len + module_basename_len;
  LPWSTR image =
    HeapAlloc(GetProcessHeap(), 0, (image_len + 1) * sizeof(WCHAR));
  if (!image || !lstrcpynW(image, cygwin_dir, prefix_len + 1))
    goto exit_process;
  /* Correct the stray double-quote from the preprocessor */
  image[prefix_len - 5] = L'\\';
  if (!lstrcpynW(image + prefix_len, module_basename, module_basename_len + 1))
    goto exit_process;

  /* 3. Compute the new command line */

  /* Get the full command line and skip its first token with image. The first
     token follows the same rules for escaping spaces as PATH does for
     semicolons: the characters themselves are all which require escaping, and
     the double-quote characters do not contribute to the string (although that
     doesn't matter here). i.e.
       C:\Program" "Files\Software\foo.exe --help
     and
       "C:\Program Files\Software\foo.exe" --help
     both refer to C:\Program Files\Software\foo.exe as being the first token.

     See stdargv.c and wincmdln.c in MSVCRT or argv_parsing.cpp and
     argv_winmain.cpp in the UCRT for confirmation. */
  LPWSTR raw_cmdline = GetCommandLineW();
  if (!raw_cmdline)
    goto exit_process;

  int in_quotes = 0;
  while (*raw_cmdline != L'\0' && (*raw_cmdline != L' ' || in_quotes)) {
    if (*raw_cmdline == L'"')
      in_quotes = !in_quotes;
    raw_cmdline++;
  }

  /* raw_cmdline is now either an empty string or points to the space following
     the program name. */

  /* If image contains a space, it'll need to be quoted in the command line */
  LPWSTR p = image;
  while (*p != '\0' && *p != ' ')
    p++;
  int image_needs_quotes = (*p != '\0');

  int raw_cmdline_len = lstrlenW(raw_cmdline);
  int cmdline_len = image_len + image_needs_quotes * 2 + raw_cmdline_len;
  LPWSTR cmdline =
    HeapAlloc(GetProcessHeap(), 0, (cmdline_len + 1) * sizeof(WCHAR));
  if (!cmdline)
    goto exit_process;

  /* Copy image and raw_cmdline to cmdline. While image cannot be an empty
     string, raw_cmdline may be. */
  if (!lstrcpynW(cmdline + image_needs_quotes, image, image_len + 1) ||
      (raw_cmdline_len > 0 &&
         !lstrcpynW(cmdline + image_needs_quotes * 2 + image_len,
                   raw_cmdline, raw_cmdline_len + 1)))
    goto exit_process;

  /* The dance above will ensure that image and raw_cmdline are written to the
     correct parts of the string, but the quotes themselves still need
     writing. */
  if (image_needs_quotes) {
    cmdline[0] = L'"';
    cmdline[image_len + 1] = L'"';
    /* If raw_cmdline is an empty string, then cmdline[image_len + 1] was the
       null terminator from when image was copied, so we need to add a new one.
       If raw_cmdline was copied, lstrcpynW already wrote the terminator. */
    if (raw_cmdline_len == 0)
      cmdline[image_len + 2] = L'\0';
  }

  /* Default startup info */
  STARTUPINFO startup;
  PROCESS_INFORMATION child;
  startup.cb = sizeof(startup);
  startup.lpReserved = NULL;
  startup.lpDesktop = NULL;
  startup.lpTitle = NULL;
  startup.dwFlags = 0;
  startup.cbReserved2 = 0;
  startup.lpReserved2 = NULL;

  /* Finally, launch the process */
  if (!CreateProcess(image, cmdline, NULL, NULL, TRUE, 0, NULL, NULL,
                     &startup, &child))
    goto exit_process;

  /* Clean-up */
  HeapFree(GetProcessHeap(), 0, current_path);
  HeapFree(GetProcessHeap(), 0, cmdline);
  HeapFree(GetProcessHeap(), 0, module_name);
  HeapFree(GetProcessHeap(), 0, image);
  CloseHandle(child.hThread);

  /* Wait for it to terminate and mirror its exit status */
  WaitForSingleObject(child.hProcess, INFINITE);
  GetExitCodeProcess(child.hProcess, &exitcode);

exit_process:
  ExitProcess(exitcode);
}
