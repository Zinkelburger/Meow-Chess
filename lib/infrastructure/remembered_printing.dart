import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../domain/model.dart';

/// Device preferences live outside tournament files and their undo history.
class PrinterPreference {
  PrinterPreference({this.directory});
  final Directory? directory;

  Future<File> get file async {
    final configured = Platform.environment['MEOW_DATA_DIR'];
    final dir =
        directory ??
        (configured == null
            ? await getApplicationSupportDirectory()
            : Directory(configured));
    return File(path.join(dir.path, 'printer.json'));
  }

  Future<Printer?> read() async {
    final f = await file;
    if (!await f.exists()) return null;
    try {
      return Printer.fromMap(jsonDecode(await f.readAsString()) as Map);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> write(Printer printer) async {
    final f = await file;
    await f.parent.create(recursive: true);
    final temporary = File('${f.path}.tmp');
    await temporary.writeAsString(jsonEncode(printer.toMap()), flush: true);
    await temporary.rename(f.path);
  }

  Future<File> get _paperFile async =>
      File(path.join((await file).parent.path, 'paper.json'));

  /// Whether this computer prints on A4; Letter unless it was chosen. A
  /// preference that cannot be read must never stop a print.
  Future<bool> readA4() async {
    if (kIsWeb) return false;
    try {
      final map = jsonDecode(await (await _paperFile).readAsString());
      return map is Map && map['size'] == 'a4';
    } catch (_) {
      return false;
    }
  }

  Future<void> writeA4(bool a4) async {
    if (kIsWeb) return;
    final f = await _paperFile;
    await f.parent.create(recursive: true);
    final temporary = File('${f.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'size': a4 ? 'a4' : 'letter'}),
      flush: true,
    );
    await temporary.rename(f.path);
  }
}

/// Whether a sheet printed on [paper] should use the A4 layout rather than
/// Letter: the one that fits, or [preferA4] when both fit (Legal, A3) or
/// neither does. Sheets are laid out for Letter and A4 only, because those are
/// the sizes every report is checked on.
bool a4LayoutFor(PdfPageFormat paper, {required bool preferA4}) {
  // Points; a driver may round a page size by a point or two.
  const slack = 3.0;
  final short = paper.width < paper.height ? paper.width : paper.height;
  final long = paper.width < paper.height ? paper.height : paper.width;
  bool fits(PdfPageFormat layout) =>
      layout.width <= short + slack && layout.height <= long + slack;
  final letter = fits(PdfPageFormat.letter), a4 = fits(PdfPageFormat.a4);
  return letter == a4 ? preferA4 : a4;
}

/// Sends exactly one job; cancellation and failures never trigger a retry.
class RememberedPrinting {
  RememberedPrinting({
    PrinterPreference? preference,
    Future<PrintingInfo> Function()? info,
    Future<List<Printer>> Function()? printers,
    Future<bool> Function(Printer?, LayoutCallback, String, PdfPageFormat)?
    send,
    this.discoveryTimeout = const Duration(seconds: 20),
  }) : preference = preference ?? PrinterPreference(),
       info = info ?? Printing.info,
       printers = printers ?? Printing.listPrinters,
       send = send ?? _send;

  static final shared = RememberedPrinting();
  final PrinterPreference preference;
  final Future<PrintingInfo> Function() info;
  final Future<List<Printer>> Function() printers;
  final Future<bool> Function(Printer?, LayoutCallback, String, PdfPageFormat)
  send;

  /// How long to wait for the computer to list its printers, normally about a
  /// second. A stuck print service must not leave the panel on "Printing…".
  final Duration discoveryTimeout;
  bool busy = false;

  /// Whether this computer prints on A4; read once at startup by [loadPaper].
  bool a4 = false;
  PdfPageFormat get pageFormat => a4 ? PdfPageFormat.a4 : PdfPageFormat.letter;

  Future<void> loadPaper() async => a4 = await preference.readA4();

  Future<void> setPaper(bool value) async {
    a4 = value;
    await preference.writeA4(value);
  }

  /// The layout the last job went out in: true for A4, false for Letter, null
  /// before any. It differs from the preview when the printer's paper did.
  bool? printedA4;

  /// Just before a job goes out, the plugin says what paper it is going on,
  /// and the sheet is laid out again if it was built for the other size, so a
  /// Letter tray never cuts off the bottom of an A4 sheet. Windows reports the
  /// printer's real paper, and the print window reports the TD's choice. A
  /// direct print on Linux reports only the language's default, so there the
  /// Paper setting stands and CUPS fits the sheet to the tray.
  LayoutCallback _layout(
    Uint8List bytes, {
    required bool builtA4,
    required bool trustPaper,
    Future<Uint8List> Function(bool a4)? relayout,
  }) => (paper) async {
    final want = trustPaper ? a4LayoutFor(paper, preferA4: builtA4) : builtA4;
    if (want == builtA4 || relayout == null) {
      printedA4 = builtA4;
      return bytes;
    }
    final relaid = await relayout(want);
    printedA4 = want;
    return relaid;
  };

  /// Paper, tray and two-sided printing come from the printer's own settings,
  /// or from the system print window; a forced custom page size can stall a
  /// driver and discards those settings. False from a direct print means the
  /// job failed, as nothing was offered to cancel; from the window, cancelled.
  static Future<bool> _send(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
  ) async {
    try {
      if (printer == null) {
        return await Printing.layoutPdf(
          onLayout: onLayout,
          name: name,
          format: format,
          // On macOS this is what puts paper size in the print window, and
          // lays the sheet out again when it changes.
          dynamicLayout: true,
          usePrinterSettings: true,
          // The classic Windows window is print setup, with no copies field.
          windowsModernDialog: true,
        );
      }
      // Windows' plugin never answers for a printer that has gone away since
      // it was listed, so look once more just before sending.
      final listed = await Printing.listPrinters().timeout(
        const Duration(seconds: 20),
      );
      if (!listed.any((p) => p.url == printer.url)) throw 'Printer not found';
      final sent = Future.value(
        Printing.directPrintPdf(
          printer: printer,
          onLayout: onLayout,
          name: name,
          format: format,
          dynamicLayout: false,
          usePrinterSettings: true,
        ),
      );
      if (await sent.timeout(const Duration(minutes: 3))) {
        return true;
      }
      throw printer.name;
    } on TimeoutException {
      // It may yet print, so this must not invite a second copy.
      throw TournamentException(
        '${printer?.name ?? 'The printer'} is not responding. Look in this '
        'computer\'s print queue before printing again.',
      );
    } catch (error) {
      // The plugin reports failures as bare strings, such as "Printer not
      // found" for a printer that has gone away since it was listed.
      final who = printer == null ? 'The printer' : printer.name;
      throw TournamentException(
        '$who did not accept the job${error is String && error != who ? ' ($error)' : ''}. '
        'Check that it is on, then try again or use Save PDF.',
      );
    }
  }

  /// GTK lists these beside real printers. Print to File writes wherever GTK
  /// last wrote, with no prompt, and Print to LPR needs a tool few computers
  /// have; Save PDF does the first properly. CUPS names cannot contain spaces,
  /// so no real queue is hidden.
  static const _gtkPseudoPrinters = {'Print to File', 'Print to LPR'};

  /// The printers that can take a job right now.
  Future<List<Printer>> available() async {
    final List<Printer> found;
    try {
      found = await printers().timeout(discoveryTimeout);
    } on TimeoutException {
      throw const TournamentException(
        'This computer\'s print service is not responding, so no printers '
        'could be listed. Check that it is running, or use Save PDF in the '
        'print panel.',
      );
    }
    return [
      for (final p in found)
        if (p.isAvailable &&
            !(!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.linux &&
                _gtkPseudoPrinters.contains(p.name)))
          p,
    ];
  }

  /// The system print window, for copies, two-sided printing, trays and
  /// printers the saved one does not cover. It never changes the saved printer.
  Future<bool> printWithDialog(
    Uint8List bytes,
    String name, {
    bool Function()? canSend,
    bool? builtA4,
    Future<Uint8List> Function(bool a4)? relayout,
  }) async {
    if (busy) return false;
    busy = true;
    try {
      if (!(await info()).canPrint) {
        throw const TournamentException(
          'Printing is not available on this computer.',
        );
      }
      if (canSend != null && !canSend()) return false;
      printedA4 = null;
      return await send(
        null,
        _layout(
          bytes,
          builtA4: builtA4 ?? a4,
          trustPaper: true,
          relayout: relayout,
        ),
        name,
        pageFormat,
      );
    } finally {
      busy = false;
    }
  }

  /// [bytes] is the sheet as laid out for [builtA4] (the Paper setting when
  /// null); [relayout] builds it for the other size, if the printer's paper
  /// turns out to be that.
  Future<bool> print(
    Uint8List bytes,
    String name, {
    required Future<Printer?> Function(List<Printer>) choose,
    bool changePrinter = false,
    // Recheck snapshot validity after asynchronous discovery or selection.
    bool Function()? canSend,
    void Function(Object)? onPreferenceError,
    bool? builtA4,
    Future<Uint8List> Function(bool a4)? relayout,
  }) async {
    if (busy) return false;
    busy = true;
    printedA4 = null;
    LayoutCallback layout({required bool trustPaper}) => _layout(
      bytes,
      builtA4: builtA4 ?? a4,
      trustPaper: trustPaper,
      relayout: relayout,
    );
    try {
      final capabilities = await info();
      if (!capabilities.canPrint) {
        throw const TournamentException(
          'Printing is not available on this computer.',
        );
      }
      if (!capabilities.directPrint || !capabilities.canListPrinters) {
        if (canSend != null && !canSend()) return false;
        return await send(null, layout(trustPaper: true), name, pageFormat);
      }
      final found = await available();
      if (found.isEmpty) {
        throw const TournamentException(
          'No printers are available. Add one in this computer\'s printer '
          'settings and try again, or use Save PDF in the print panel.',
        );
      }
      Printer? saved;
      try {
        saved = await preference.read();
      } catch (e) {
        onPreferenceError?.call(e);
      }
      var printer = changePrinter
          ? null
          : found.where((p) => p.url == saved?.url).firstOrNull;
      printer ??= await choose(found);
      if (printer == null || (canSend != null && !canSend())) return false;
      final success = await send(
        printer,
        layout(
          trustPaper: kIsWeb || defaultTargetPlatform != TargetPlatform.linux,
        ),
        name,
        pageFormat,
      );
      if (success) {
        try {
          await preference.write(printer);
        } catch (e) {
          onPreferenceError?.call(e);
        }
      }
      return success;
    } finally {
      busy = false;
    }
  }
}
