// Meow-Chess entry point into BBP Pairings: the `--dutch input -p` path of
// src/main.cpp, reading the tournament from memory and returning the pairs as
// text, so the app needs neither a helper executable nor temporary files.

#include <cstring>
#include <exception>
#include <list>
#include <new>
#include <sstream>
#include <string>

#include "fileformats/trf.h"
#include "fileformats/types.h"
#include "swisssystems/common.h"
#include "tournament/tournament.h"

namespace
{
  // Copies [text] into the caller's buffer, always NUL-terminated. Returns
  // the full length so the caller can retry with a larger buffer.
  int copyOut(const std::string &text, char *out, int capacity)
  {
    if (out && capacity > 0)
    {
      const std::size_t n =
        text.size() < static_cast<std::size_t>(capacity - 1)
          ? text.size()
          : static_cast<std::size_t>(capacity - 1);
      std::memcpy(out, text.data(), n);
      out[n] = '\0';
    }
    return static_cast<int>(text.size());
  }
}

extern "C"
{
#if defined(_WIN32)
  __declspec(dllexport)
#else
  __attribute__((visibility("default")))
#endif
  /**
   * Pairs the next round of the TRF-2026 tournament [trf] with the FIDE Dutch
   * system. On success writes "count\n" then one "white black" line per pair
   * (black 0 for the pairing-allocated bye), using TRF starting ranks, and
   * returns 0. Otherwise writes the reason and returns BBP Pairings' exit
   * code: 1 no valid pairing, 2 unexpected error, 3 invalid input, 4 too
   * large. A return value written beyond [capacity] is truncated; the
   * function's result length is reported through [length].
   */
  int meow_bbp_pair_dutch(
    const char *trf,
    char *out,
    int capacity,
    int *length)
  {
    std::string result;
    int code = 0;
    try
    {
      std::istringstream input{std::string(trf)};
      tournament::Tournament tournament =
        fileformats::trf::readFile(input, true);
      if (tournament.initialColor == tournament::COLOR_NONE)
      {
        result = "The initial piece colour is not configured.";
        code = 3;
      }
      else
      {
        tournament.updateRanks();
        tournament.computePlayerData();
        const swisssystems::Info &info =
          swisssystems::getInfo(swisssystems::DUTCH);
        if (tournament.defaultAcceleration)
        {
          for (
            tournament::round_index round_index{ };
            round_index <= tournament.playedRounds;
            ++round_index)
          {
            info.updateAccelerations(tournament, round_index);
          }
        }
        std::list<swisssystems::Pairing> pairs =
          info.computeMatching(tournament::Tournament(tournament), nullptr);
        swisssystems::sortResults(pairs, tournament);
        std::ostringstream text;
        text << pairs.size() << '\n';
        for (const swisssystems::Pairing &pair : pairs)
        {
          text << pair.white + 1u << ' '
            << (pair.white == pair.black ? 0u : pair.black + 1u) << '\n';
        }
        result = text.str();
      }
    }
    catch (const swisssystems::NoValidPairingException &exception)
    {
      result = std::string("No valid pairing exists: ") + exception.what();
      code = 1;
    }
    catch (const swisssystems::UnapplicableFeatureException &exception)
    {
      result = exception.what();
      code = 3;
    }
    catch (const fileformats::FileFormatException &exception)
    {
      result = exception.what();
      code = 3;
    }
    catch (const fileformats::FileReaderException &exception)
    {
      result = exception.what();
      code = 3;
    }
    catch (const tournament::BuildLimitExceededException &exception)
    {
      result = exception.what();
      code = 4;
    }
    catch (const std::bad_alloc &)
    {
      result = "The pairing engine ran out of memory.";
      code = 4;
    }
    catch (const std::exception &exception)
    {
      result = exception.what();
      code = 2;
    }
    catch (...)
    {
      result = "The pairing engine failed unexpectedly.";
      code = 2;
    }
    const int n = copyOut(result, out, capacity);
    if (length) *length = n;
    return code;
  }
}
