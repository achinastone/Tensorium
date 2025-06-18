// using byte pair encoding/decoding tokenizer
//  https://en.wikipedia.org/wiki/Byte-pair_encoding
unit uTokenizer;
{$ifdef FPC}
  {$mode Delphi}
  {$ModeSwitch advancedrecords}
{$endif}
{$i-}

interface
uses SysUtils, ntensors;

const BPE_PIECE_LEN = $200;

type
  TTokenIndex = record
    str : ansistring;
    id : longint;
  end;

  { TTokenizerBPE }

  TTokenizerBPE= record
    vocab : TArray<ansistring>;
    vocabScores : TArray<Single>;
    sortedVocab: TArray<TTokenIndex>;
    //vocabSize : longint;
    maxTokenLength : longword;
    bytePieces: array[0..BPE_PIECE_LEN-1] of byte; // stores all single-byte strings
    constructor create(const filename:string; const aVocabSize:SizeInt);
    function vocabSize():SizeInt;
    function lookup(const str:ansistring):longint;
    function decode(const prevToken, token:longint):ansistring;
    procedure encode(const aText: ansistring; const bos, eos: boolean; var tokens: TArray<longint>);  overload;
    function encode(const aText: ansistring; const bos, eos:boolean):TArray<longint>;                 overload;
  private
    class function compareTokens(const a, b: TTokenIndex): SizeInt;static;
  end;

implementation

function charIsSpace(const c:ansichar):boolean;inline;
begin
  result := c in [#$A, #$D, #$20]
end;

function charIsAnsi(const c:ansichar):boolean;inline;
begin
  result := c in [#$20..#$7E]
end;

{ TTokenizerBPE }

constructor TTokenizerBPE.create(const filename: string; const aVocabSize: SizeInt);
var
  i, len:longint;
  f : file;

begin
  // i should have written the vocabSize into the tokenizer file... sigh
  // malloc space to hold the scores and the strings
  assert(fileExists(filename), '['+fileName+'] does not exist');
  setLength(vocab, aVocabSize);
  setLength(vocabScores, aVocabSize);
  sortedVocab := nil; // initialized lazily
  for i:=0 to (BPE_PIECE_LEN div 2)-1 do begin
      bytePieces[i * 2] := i;
      bytePieces[i * 2 + 1] := 0;
  end;
  // read in the file
  assignFile(f, filename);
  reset(f, 1);
  BlockRead(f, maxTokenLength, sizeOf(maxTokenLength));
  if IOResult=0 then
    for i:=0 to length(vocab)-1 do begin
      BlockRead(f, vocabScores[i], sizeOf(single));
      BlockRead(f, len, sizeof(len));
      if IOResult<>0 then break;
      if len<=0 then continue;
      SetLength(vocab[i], len);
      BlockRead(f, vocab[i][1], len);
      if IOResult<>0 then break
    end;
  closeFile(f);
end;

class function TTokenizerBPE.compareTokens(const a, b:TTokenIndex):SizeInt;
begin
    result := CompareStr(a.str, b.str);
end;

function TTokenizerBPE.vocabSize(): SizeInt;
begin
  exit(length(vocab))
end;

type TTokenTools=TTools<TTokenIndex>;
function TTokenizerBPE.lookup(const str: ansistring): longint;
var  tok: TTokenIndex;
begin
  tok.str:=str;
  result := TTokenTools.BinSearch(pointer(sortedVocab), tok, high(sortedVocab),compareTokens);
  if result>=0 then
    result := sortedVocab[result].id
  else
    result := -1;
end;

function TTokenizerBPE.decode(const prevToken, token: longint): ansistring;
var byteVal : byte;
begin
  assert(assigned(vocab), 'No tokenizer, load a tokenizer file first!');
  result := vocab[token];
  // following BOS (1) token, sentencepiece decoder strips any leading whitespace (see PR #89)
  if (prevToken = 1) and (result[1]=' ') then delete(result, 1, 1);
  // careful, some tokens designate raw bytes, and look like e.g. '<0x01>'
  // parse this and convert and return the actual byte
  byteVal :=0;
  if pos('<0x', result)>0 then begin
    byteVal := StrToInt('$'+Copy(result, 4, 2));
    result := PAnsiChar(@bytePieces[0]) + byteVal*2
  end;
end;

procedure TTokenizerBPE.encode(const aText: ansistring; const bos, eos: boolean; var tokens: TArray<longint>);
var
  i, j, id
    //,str_len
    //,dummy_prefix
    : longint;
  str_buffer : ansistring;
  c : ansichar;
  best_score : single;
  best_id, best_idx: longint;
begin
  // encode the string text (input) into an upper-bound preallocated tokens[] array
  // bos != 0 means prepend the BOS token (=1), eos != 0 means append the EOS token (=2)
  assert(assigned(vocab), 'No tokenizer, load a tokenizer file first!');
  assert(aText<>'', 'cannot encode NULL text.');
  //assert(assigned(tokens), '<tokens> cannot''t be "nil"');

  if not assigned(sortedVocab) then begin
      // lazily malloc and sort the vocabulary
      setLength(sortedVocab, length(vocab));
      for i := 0 to high(sortedVocab) do begin
          sortedVocab[i].str := vocab[i];
          sortedVocab[i].id := i;
      end;
      TTokenTools.QuickSort(pointer(sortedVocab), 0, High(sortedVocab), compareTokens());
  end;

  // create a temporary buffer that will store merge candidates of always two consecutive tokens
  // *2 for concat, +1 for null terminator +2 for UTF8 (in case max_token_length is 1)
  //char* str_buffer = malloc((t->max_token_length*2 +1 +2) * sizeof(char));
  //size_t str_len = 0;
  //setLength(str_buffer, maxTokenLength*2 +1 +2);
  str_buffer :='';
  //str_len := 1;
  // start at 0 tokens
  //n_tokens^ := 0;

  // add optional BOS (=1) token, if desired
  if bos then begin
    insert(1, tokens, length(tokens));
    //tokens[n_tokens^] := 1;
    //inc(n_tokens^);
  end;

  // add_dummy_prefix is true by default
  // so prepend a dummy prefix token to the input string, but only if text != ""
  // TODO: pretty sure this isn't correct in the general case but I don't have the
  // energy to read more of the sentencepiece code to figure out what it's doing
  if AText[1] <> #0 then begin
      insert(lookup(' '), tokens, length(tokens));
      //tokens[n_tokens^] := lookup(' ');
      //inc(n_tokens^)
  end;

  // Okay UTF-8 time. This will get messy. Here is the reference from Wikipedia:
  // Code point ↔ UTF-8 conversion
  // First code point	Last code point	Byte 1	Byte 2	Byte 3	Byte 4
  // U+0000	U+007F	    0xxxxxxx
  // U+0080	U+07FF	    110xxxxx	10xxxxxx
  // U+0800	U+FFFF	    1110xxxx	10xxxxxx	10xxxxxx
  // U+10000	U+10FFFF    11110xxx	10xxxxxx	10xxxxxx	10xxxxxx

  // process the raw (UTF-8) byte sequence of the input string
  for i:=1 to length(aText) do begin
      c := aText[i];
      // reset buffer if the current byte is ASCII or a leading byte
      // 0xC0 is 11000000, so (*c & 0xC0) keeps the first 2 bits and zeros the rest
      // 0x80 is 10000000
      // in UTF-8, all continuation bytes start with "10" in first two bits
      // so in English this is: "if this byte is not a continuation byte"
      if ( byte(c) and $C0) <> $80 then begin
          // this byte must be either a leading byte (11...) or an ASCII char (0x...)
          // => reset our location, as we're starting a new UTF-8 codepoint
          str_buffer := '';
      end;

      // append the current byte to the buffer
      //str_buffer[str_len] := c; // ++ is post-increment, incremented after this line
      insert(c, str_buffer, length(str_buffer)+1);
      //inc(str_len);
      //str_buffer[str_len] := #0;

      // while the next character is a continuation byte, continue appending
      // but if there are too many of them, just stop to avoid overruning str_buffer size.
      if (i<length(aText)) and ((byte(aText[i+1]) and $C0 = $80) and (length(str_buffer) <= 4)) then
          continue;

      // ok c+1 is not a continuation byte, so we've read in a full codepoint
      id := lookup(str_buffer);

      if id > -1 then begin
          // we found this codepoint in vocab, add it as a token
          insert(id, tokens, length(tokens));
          //tokens[n_tokens^] := id;
          //inc(n_tokens^)
      end else begin
          // byte_fallback encoding: just encode each byte as a token
          // +3 is here because the first 3 vocab elements are <unk>, <s>, </s>
          // so the individual bytes only start at index 3
          for j:=1 to length(str_buffer) do begin
              insert(byte(str_buffer[j]) + 3, tokens, length(tokens));
              //tokens[n_tokens^] := byte(str_buffer[j]) + 3;
              //inc(n_tokens^)
          end;
      end;
      str_buffer := ''; // protect against a sequence of stray UTF8 continuation bytes
  end;

  // merge the best consecutive pair each iteration, according the scores in vocab_scores
  while true do begin
      best_score := -1e10;
      best_id := -1;
      best_idx := -1;

      for i:=0 to length(tokens)-2 do begin
          // check if we can merge the pair (tokens[i], tokens[i+1])
          str_buffer := vocab[tokens[i]]+vocab[tokens[i+1]];
          id := lookup(str_buffer);
          if (id > -1) and (vocabScores[id] > best_score) then begin
              // this merge pair exists in vocab! record its score and position
              best_score := vocabScores[id];
              best_id := id;
              best_idx := i;
          end;
      end;

      if best_idx = -1 then
          break; // we couldn't find any more pairs to merge, so we're done

      // merge the consecutive pair (best_idx, best_idx+1) into new token best_id
      tokens[best_idx] := best_id;
      // delete token at position best_idx+1, shift the entire sequence back 1
      for i := best_idx+1 to length(tokens)-2 do
          tokens[i] := tokens[i+1];
      delete(tokens, high(tokens), 1)
      //dec(n_tokens^); // token length decreased
  end;

  // add optional EOS (=2) token, if desired
  if eos then begin
    insert(2, tokens, length(tokens));
    //tokens[n_tokens^] := 2;
    //inc(n_tokens^)
  end;

end;

function TTokenizerBPE.encode(const aText: ansistring; const bos, eos: boolean): TArray<longint>;
begin
  encode(aText, bos, eos, result)
end;

//var tok :TTokenizerBPE;
//  s:string;
//  i:longint;
//  tokens:TArray<longint>;
initialization
  //setLength(tokens, 100);
  //tok := TTokenizerBPE.create('tokenizer.bin', 32000);
  //s:='';
  //tok.encode('this is a dog', true, false, tokens);
  //for i:=0 to high(tokens)-1 do begin
  //  s:=s+tok.decode(tokens[i], tokens[i+1]);
  //end;

end.

