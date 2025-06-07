function escapeString(input: string): string {
  const hex = "0123456789abcdef";
  let result = "";

  for (let i = 0; i < input.length; i++) {
    const c = input.charCodeAt(i);

    if (c < 0x20) {
      result += "\\u00";
      result += hex[(c >> 4) & 0xf];
      result += hex[c & 0xf];
    } else {
      switch (input[i]) {
        case '"':
          result += '\\"';
          break;
        case "\\":
          result += "\\\\";
          break;
        case "\n":
          result += "\\n";
          break;
        case "\r":
          result += "\\r";
          break;
        case "\t":
          result += "\\t";
          break;
        case "|":
          result += "\\|";
          break;
        default:
          result += input[i];
      }
    }
  }

  return result;
}

function unescapeString(input: string): string {
  let result = "";
  for (let i = 0; i < input.length; i++) {
    const c = input[i];

    if (c === "\\") {
      const next = input[i + 1];
      switch (next) {
        case "n":
          result += "\n";
          i++;
          break;
        case "r":
          result += "\r";
          i++;
          break;
        case "t":
          result += "\t";
          i++;
          break;
        case '"':
          result += '"';
          i++;
          break;
        case "\\":
          result += "\\";
          i++;
          break;
        case "|":
          result += "|";
          i++;
          break;
        case "u":
          if (input[i + 2] === "0" && input[i + 3] === "0") {
            const hex = input.slice(i + 4, i + 6);
            if (hex.length === 2 && /^[0-9a-fA-F]{2}$/.test(hex)) {
              result += String.fromCharCode(parseInt(hex, 16));
              i += 5; // skip \u00XX
              break;
            }
          }
        // fallthrough if invalid
        default:
          result += c; // just emit the backslash if it's unknown
          break;
      }
    } else {
      result += c;
    }
  }
  return result;
}

const raw = "the qu|ick brown\n \rfox jumped\tover the lazy dawg >w< \\|";
const escaped = escapeString(raw);
const unescaped = unescapeString(escaped);

console.log("raw:", raw);
console.log("escaped:", escaped);
console.log("unescaped:", unescaped);
