unit SDLPort;

interface

  type TPalette = Array[0..255,0..2] of byte;
  type TCloseCallback = procedure;
  type AnsiStringCP865 = type AnsiString(865);
  type TCharToUTF8Table = array[#128..#255] of RawByteString;

  function GetVersion : string;

  procedure Init;
  procedure DeinitGraphics;
  procedure Deinit;

  procedure SetCloseCallback(callback : TCloseCallback);
  procedure SetPalette(input : TPalette);
  procedure Render(buffer : array of byte);
  procedure WaitRaster;

  function KeyPressed : boolean;
  procedure WaitForKeyPress(var ch1, ch2 : char);

  procedure Wait(ms : integer);

  function IsCP865(s : string): boolean;
  function ConvertToUTF8(s : string): UTF8String;

implementation

  uses sdl2, getopts;
  const version: string = 'SP5';
        xRes = 320;
        yRes = 200;
        targetFrames = 70;
        aspectRes: real = xRes / yRes;

  var windowMultiplier: integer;
      window: PSDL_Window;
      renderer: PSDL_Renderer;
      originalSurface: PSDL_Surface;
      displaySurface: PSDL_Surface;
      displayTexture: PSDL_Texture;
      palette: array[0..255] of TSDL_Color;
      renderDestRect: TSDL_Rect;

      windowResized: boolean;
      fullScreen: boolean;
      aspect: real;

      timer: TSDL_TimerID;
      frameCount, lastFrameCount, subFrameCount, lastFrameTick: LongInt;
      closeCallback: TCloseCallback;

      swRendering: boolean;

procedure GetArguments;
var c : char;
    optionindex : Longint;
    options : array[1..1] of TOption;

begin
  with options[1] do
  begin
    name:='--sw-rendering';
    has_arg:=0;
    flag:=nil;
    value:=#0;
  end;
  c:=#0;
  optionindex:=0;
  repeat
    c:=getlongopts('s', @options[1], optionindex);
    case c of
      #0 : begin
        if (options[optionindex].name = '--sw-rendering') then
        begin
          swRendering := true;
        end;
      end;
      's' : swRendering := true;
    end; { case }
  until c=endofoptions;
end;

function TimerCallback(interval: UInt32; param: Pointer): UInt32; cdecl;
var frameIntervalMs, nowMs, elapsed : LongInt;
begin
  frameIntervalMs := 1000 div targetFrames;
  nowMs := SDL_GetTicks();
  elapsed := nowMs - lastFrameTick;
  if (elapsed >= frameIntervalMs) then
  begin
    lastFrameTick := nowMs;
    subFrameCount += elapsed;

    while (subFrameCount >= frameIntervalMs) do
    begin
        dec(subFrameCount, frameIntervalMs);
        inc(framecount);
    end;
  end;
  TimerCallback:=interval;
end;

procedure GetRenderRect(var rect : TSDL_Rect);
var windowW, windowH, h, w: LongInt;
begin
  SDL_GetRendererOutputSize(renderer, @windowW, @windowH);
  if (windowW / windowH <= aspect) then
  begin
    h := round(windowW / aspect);
    rect.x := 0;
    rect.y := (windowH - h) div 2;
    rect.w := windowW;
    rect.h := h;
  end
  else
  begin
    w := round(windowH * aspect);
    rect.x := (windowW - w) div 2;
    rect.y := 0;
    rect.w := w;
    rect.h := windowH;
  end;
end;

procedure RefreshRendering;
begin
  GetRenderRect(renderDestRect);
end;

procedure ResetWindowSize;
begin
  SDL_SetWindowSize(window, xRes * windowMultiplier, Round(yRes * windowMultiplier * aspectRes / aspect));
  windowResized := true;
end;

function GetVersion: string;
begin
  GetVersion := version;
end;

procedure Init;
var rendererFlags : UInt32;
begin
  rendererFlags := 0;
  windowMultiplier := 2;
  aspect := aspectRes;
  swRendering := false;

  GetArguments;

  if SDL_Init( SDL_INIT_VIDEO or SDL_INIT_TIMER ) < 0 then HALT;

  window := SDL_CreateWindow('Ski Jump International v3',
            SDL_WINDOWPOS_UNDEFINED,
            SDL_WINDOWPOS_UNDEFINED,
            xRes * windowMultiplier,
            yRes * windowMultiplier,
            SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE);
  if window = nil then Halt;

  if (swRendering = true) then
  begin
    rendererFlags := rendererFlags OR SDL_RENDERER_SOFTWARE;
  end;

  renderer := SDL_CreateRenderer(window, -1, rendererFlags);
  if renderer = nil then Halt;

  // 8-bit surface for original data
  originalSurface := SDL_CreateRGBSurface(0, xRes, yRes, 8, 0, 0, 0, 0);
  if originalSurface = nil then Halt;

  // 32-bit display surface for converting 8-bit data to 32-bit
  displaySurface := SDL_CreateRGBSurface(0, xRes, yRes, 32, 0, 0, 0, 0);
  if displaySurface = nil then Halt;

  // Finally a texture for displaying 32-bit display data
  displayTexture := SDL_CreateTexture(renderer,
                 SDL_PIXELFORMAT_RGBA8888,
                 SDL_TEXTUREACCESS_STREAMING,
                 xRes,
                 yRes);
  if displayTexture = nil then Halt;

  RefreshRendering();

  windowResized := false;
  fullScreen := false;

  frameCount := 0;
  lastFrameCount := 0;
  subFrameCount := 0;
  lastFrameTick := SDL_GetTicks();

  timer := SDL_AddTimer(1, TimerCallback, nil);

  closeCallback := nil;
end;

procedure DeinitGraphics;
begin
  SDL_RemoveTimer(timer);
  SDL_FreeSurface(originalSurface);
  SDL_FreeSurface(displaySurface);
  SDL_DestroyTexture(displayTexture);
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
end;

procedure Deinit;
begin
  SDL_Quit;
end;

procedure SetPalette(input : TPalette);
var index : integer;
begin
  for index:=0 to 255 do
   begin
     palette[index].r:=input[index,0] shl 2;
     palette[index].g:=input[index,1] shl 2;
     palette[index].b:=input[index,2] shl 2;
  end;

  SDL_SetPaletteColors(originalSurface^.format^.palette, @palette, 0, 256);
end;

procedure SetCloseCallback(callback : TCloseCallback);
begin
  closeCallback:=callback;
end;

procedure Render(buffer : array of byte);
var pixels : Pointer;
    pitch : LongInt;
begin
  if (windowResized) then
  begin
    RefreshRendering();
    windowResized := false;
  end;

  SDL_RenderClear(renderer);

  // Actual rendering
  SDL_LockSurface(originalSurface);
  Move(buffer, originalSurface^.pixels^, Sizeof(buffer));
  SDL_UnlockSurface(originalSurface);

  // Blit 8-bit surface to 32-bit surface
  SDL_BlitSurface(originalSurface, nil, displaySurface, nil);

  // Surface to texture
  SDL_LockTexture(displayTexture, nil, @pixels, @pitch);

  SDL_ConvertPixels(displaySurface^.w, displaySurface^.h,
                    displaySurface^.format^.format,
                    displaySurface^.pixels, displaySurface^.pitch,
                    SDL_PIXELFORMAT_RGBA8888,
                    pixels, pitch);

  SDL_UnlockTexture(displayTexture);

  // Render texture to display
  SDL_RenderCopy(renderer, displayTexture, nil, @renderDestRect);
  SDL_RenderPresent(renderer);
end;

procedure WaitRaster;
begin
  lastFrameCount := framecount;
  while(lastFrameCount = framecount) do
  begin
    SDL_Delay(1);
  end;
end;

function KeyPressed : boolean;
var event : TSDL_Event;
    pressed: boolean;
begin
  pressed:=false;

  while SDL_PollEvent(@event) = 1 do
  begin
    if ((event.type_= SDL_WINDOWEVENT) and
     (event.window.event = SDL_WINDOWEVENT_RESIZED)) then
    begin
      windowResized := true;
    end;

    if (event.type_= SDL_QUITEV) then
    begin
      if Assigned(closeCallback) then
      begin
        closeCallback;
      end;
    end;

    if event.type_= SDL_KEYDOWN then
    begin
      // Ignore modifier and status keys, since they did not trigger a keypress in DOS version.
      // F11, F12 and probably others were ignored too, but that would probably be counterintuitive.
      case event.key.keysym.sym of
        SDLK_LCTRL, SDLK_RCTRL,
        SDLK_LSHIFT, SDLK_RSHIFT,
        SDLK_LALT, SDLK_RALT,
        SDLK_LGUI, SDLK_RGUI,
        SDLK_CAPSLOCK, SDLK_SCROLLLOCK, SDLK_NUMLOCKCLEAR,
        SDLK_PRINTSCREEN, SDLK_SYSREQ, SDLK_PAUSE:
        ; // Keypress ignored
      else
        begin
          pressed:=true;
          SDL_PushEvent(@event);
          break;
        end;
      end;
    end;
  end;
  KeyPressed:=pressed
end;

procedure ToggleFullscreen;
var flags : UInt32;
begin
  windowResized := true;

  fullScreen := not fullScreen;
  if (fullScreen) then flags := SDL_WINDOW_FULLSCREEN_DESKTOP else flags := 0;

  SDL_SetWindowFullscreen(window, flags);
end;

procedure WaitForKeyPress(var ch1, ch2:char);
var event : TSDL_Event;
    scancode: TSDL_ScanCode;
    keyPressed: TSDL_KeyCode;
    keyMod: UInt16;
begin
  ch1:=#0;
  ch2:=#0;
  // Setting ch2 to a correct scancode value for the key pressed can be largely ignored.
  // It is only checked by the game for special keys, where ch1 is checked or assumed to be 0.
  // This also means that the game cannot differentiate between different keys producing the same character.

  while (true) do
  begin
    while SDL_PollEvent(@event) = 1 do
    begin
      if event.type_= SDL_KEYDOWN then
      begin
        scancode := event.key.keysym.scancode;
        keyPressed := event.key.keysym.sym;
        keyMod := event.key.keysym._mod;

        // SDL version specific shortcuts
        if ((keyMod and KMOD_LALT) > 0) then
        begin
          Case scancode of
            SDL_SCANCODE_RETURN :
              begin
                toggleFullscreen;
                exit
              end;
            SDL_SCANCODE_R :
              begin
                ResetWindowSize;
                exit
              end;
            SDL_SCANCODE_KP_PLUS, SDL_SCANCODE_EQUALS :
              begin
                windowMultiplier := windowMultiplier + 1;
                ResetWindowSize;
                exit
              end;
            SDL_SCANCODE_KP_MINUS, SDL_SCANCODE_MINUS :
              begin
                if (windowMultiplier > 1) then
                begin
                  windowMultiplier := windowMultiplier - 1;
                  ResetWindowSize;
                  exit
                end;
              end;
            SDL_SCANCODE_A :
              begin
                if (aspect <> aspectRes) then
                  aspect := aspectRes
                else
                  aspect := 4 / 3;
                ResetWindowSize;
                exit;
              end;
          end;
        end;

        // Special cases for key combinations used throughout the game.
        // Check for Right Alt/AltGr first, since pressing it can make Left Ctrl look as pressed too.
        if ((keyMod and KMOD_MODE) > 0) then exit;
        if ((keyMod and KMOD_RALT) > 0) then exit;
        if ((keyMod and KMOD_LALT) > 0) then
        begin
          Case keyPressed of
            SDLK_x: begin ch1:=#0; ch2:=#45; exit end; {ALT-X}
          else
            exit
          end;
        end;
        if ((keyMod and KMOD_CTRL) > 0) then
        begin
          Case keyPressed of
            SDLK_c: begin ch1:=#3; exit end; {CTRL-C}
          else
            exit
          end;
        end;
        if ((keyMod and KMOD_GUI) > 0) then exit;

        // Handle conversion of letters to uppercase.
        // Convert only if Caps Lock is off and Shift is pressed or vice versa.
        if (
            ((keyMod and KMOD_SHIFT) > 0) xor ((keyMod and KMOD_CAPS) > 0)
        ) then
        begin
          Case keypressed of
            97..122, 224..246, 248..254: keyPressed:=TSDL_KeyCode(keyPressed - 32);
          end;
        end;

        // If modifier is Shift, convert the key pressed accordingly.
        // For special keys, standard US QWERTY layout is assumed.
        if ((keyMod and KMOD_SHIFT) > 0) then
        begin
          Case keyPressed of
            65..90, 97..122, 190..214, 216..222, 224..246, 248..254: ; // Already handled above
            SDLK_1 : keyPressed:=SDLK_EXCLAIM;
            SDLK_2 : keyPressed:=SDLK_AT;
            SDLK_3 : keyPressed:=SDLK_HASH;
            SDLK_4 : keyPressed:=SDLK_DOLLAR;
            SDLK_5 : keyPressed:=SDLK_PERCENT;
            SDLK_6 : keyPressed:=SDLK_CARET;
            SDLK_7 : keyPressed:=SDLK_AMPERSAND;
            SDLK_8 : keyPressed:=SDLK_ASTERISK;
            SDLK_9 : keyPressed:=SDLK_LEFTPAREN;
            SDLK_0 : keyPressed:=SDLK_RIGHTPAREN;
            SDLK_MINUS : keyPressed:=SDLK_UNDERSCORE;
            SDLK_EQUALS : keyPressed:=SDLK_PLUS;
            SDLK_LEFTBRACKET : keyPressed:=TSDL_KeyCode('{');
            SDLK_RIGHTBRACKET : keyPressed:=TSDL_KeyCode('}');
            SDLK_SEMICOLON : keyPressed:=SDLK_COLON;
            SDLK_QUOTE : keyPressed:=SDLK_QUOTEDBL;
            SDLK_BACKQUOTE : keyPressed:=TSDL_KeyCode('~');
            SDLK_BACKSLASH : keyPressed:=TSDL_KeyCode('|');
            SDLK_COMMA : keyPressed:=SDLK_LESS;
            SDLK_PERIOD : keyPressed:=SDLK_GREATER;
            SDLK_SLASH : keyPressed:=SDLK_QUESTION;
          else
            exit
          end;
        end;

        // If NumLock modifier is not set, convert the charaters accordingly
        if ((keyMod and KMOD_NUM) = 0) then
        begin
          Case keyPressed of
            SDLK_KP_1 : keyPressed:=SDLK_END;
            SDLK_KP_2 : keyPressed:=SDLK_DOWN;
            SDLK_KP_3 : keyPressed:=SDLK_PAGEDOWN;
            SDLK_KP_4 : keyPressed:=SDLK_LEFT;
            SDLK_KP_5 : begin ch1:=#0; ch2:=#76; exit end;
            SDLK_KP_6 : keyPressed:=SDLK_RIGHT;
            SDLK_KP_7 : keyPressed:=SDLK_HOME;
            SDLK_KP_8 : keyPressed:=SDLK_UP;
            SDLK_KP_9 : keyPressed:=SDLK_PAGEUP;
            SDLK_KP_0 : keyPressed:=SDLK_INSERT;
            SDLK_KP_PERIOD : keyPressed:=SDLK_DELETE;
          end;
        end;

        // Merge keypad characters with their regular counterparts.
        // It is not needed to differentiate between them, since the scancode isn't checked for normal characters.
        // Checks for Shift and Num Lock were already done, so they won't interfere with the merge.
        Case keyPressed of
          SDLK_KP_DIVIDE : keyPressed:=SDLK_SLASH;
          SDLK_KP_MULTIPLY : keyPressed:=SDLK_ASTERISK;
          SDLK_KP_MINUS : keyPressed:=SDLK_MINUS;
          SDLK_KP_PLUS : keyPressed:=SDLK_PLUS;
          SDLK_KP_ENTER : keyPressed:=SDLK_RETURN;
          SDLK_KP_1 : keyPressed:=SDLK_1;
          SDLK_KP_2 : keyPressed:=SDLK_2;
          SDLK_KP_3 : keyPressed:=SDLK_3;
          SDLK_KP_4 : keyPressed:=SDLK_4;
          SDLK_KP_5 : keyPressed:=SDLK_5;
          SDLK_KP_6 : keyPressed:=SDLK_6;
          SDLK_KP_7 : keyPressed:=SDLK_7;
          SDLK_KP_8 : keyPressed:=SDLK_8;
          SDLK_KP_9 : keyPressed:=SDLK_9;
          SDLK_KP_0 : keyPressed:=SDLK_0;
          SDLK_KP_PERIOD : keyPressed:=SDLK_PERIOD;
          SDLK_KP_EQUALS : keyPressed:=SDLK_EQUALS;
        end;

        Case keyPressed of
          SDLK_RETURN : ch1:=#13;
          SDLK_ESCAPE : ch1:=#27;
          SDLK_BACKSPACE : ch1:=#8;
          SDLK_TAB : ch1:=#9;

          32..126 : ch1:=chr(keyPressed);

          // Special characters supported by the game, OEM 865 nordic encoding is used for ch1 values
          196 : begin ch1:=#142; exit end; // A with diaeresis
          197 : begin ch1:=#143; exit end; // A with ring above
          198 : begin ch1:=#146; exit end; // AE
          214 : begin ch1:=#153; exit end; // O with diaeresis
          216 : begin ch1:=#157; exit end; // O with stroke
          220 : begin ch1:=#154; exit end; // U with diaeresis
          223 : begin ch1:=#225; exit end; // sharp s

          228 : begin ch1:=#132; ch2:=#36; exit end; // a with diaeresis
          229 : begin ch1:=#134; ch2:=#26; exit end; // a with ring above
          230 : begin ch1:=#145; exit end; // ae
          246 : begin ch1:=#148; ch2:=#39; exit end; // o with diaeresis
          248 : begin ch1:=#158; exit end; // o with stroke
          252 : begin ch1:=#129; exit end; // u with diaeresis
        end;

        Case keyPressed of
          SDLK_F1 : ch2:=#59;
          SDLK_F2 : ch2:=#60;
          SDLK_F3 : ch2:=#61;
          SDLK_F4 : ch2:=#62;
          SDLK_F5 : ch2:=#63;
          SDLK_F6 : ch2:=#64;
          SDLK_F7 : ch2:=#65;
          SDLK_F8 : ch2:=#66;
          SDLK_F9 : ch2:=#67;
          SDLK_F10 : ch2:=#68;

          SDLK_LEFT : ch2:=#75;
          SDLK_RIGHT : ch2:=#77;
          SDLK_UP : ch2:=#72;
          SDLK_DOWN : ch2:=#80;

          SDLK_INSERT : ch2:=#82;
          SDLK_DELETE : ch2:=#83;
          SDLK_HOME : ch2:=#71;
          SDLK_END : ch2:=#79;
          SDLK_PAGEUP : ch2:=#73;
          SDLK_PAGEDOWN : ch2:=#81;

          SDLK_a : ch2:=#30;
          SDLK_b : ch2:=#48;
          SDLK_c : ch2:=#46;
          SDLK_d : ch2:=#32;
          SDLK_e : ch2:=#18;
          SDLK_f : ch2:=#33;
          SDLK_g : ch2:=#34;
          SDLK_h : ch2:=#35;
          SDLK_i : ch2:=#23;
          SDLK_j : ch2:=#36;
          SDLK_k : ch2:=#37;
          SDLK_l : ch2:=#38;
          SDLK_m : ch2:=#50;
          SDLK_n : ch2:=#49;
          SDLK_o : ch2:=#24;
          SDLK_p : ch2:=#25;
          SDLK_q : ch2:=#16;
          SDLK_r : ch2:=#19;
          SDLK_s : ch2:=#31;
          SDLK_t : ch2:=#20;
          SDLK_u : ch2:=#22;
          SDLK_v : ch2:=#47;
          SDLK_w : ch2:=#17;
          SDLK_x : ch2:=#45;
          SDLK_y : ch2:=#21;
          SDLK_z : ch2:=#44;
        end;
        exit;
      end;
    end;
    SDL_Delay(10);
  end;
end;

procedure Wait(ms : integer);
begin
  SDL_Delay(ms);
end;

function IsCP865(s : string): boolean;
var i, l : integer;
begin
  l := Length(s);
  IsCP865 := false; { by default we assume it's not CP865 to not trigger unnecessary conversion if text is ASCII-only }
  for i := 1 to l do
  begin
    case s[i] of
      { sharp S / beta - only printable CP865 char in SJ3 which could be also an UTF-8 codepoint initial byte }
      #225 :
        { next 2 bytes fit continuation pattern for a 3-byte UTF-8 codepoint, so assume UTF-8 }
        { or it was some very unlikely CP865 char sequence - YOLO! }
        if (i+2 < l) and (s[i+1] in [#195..#244]) and (s[i+2] in [#195..#244]) then
          exit(false)
        { otherwise assume it was a CP865 encoded sharp S / beta }
        else
          exit(true);

      { encountered an UTF-8 codepoint initial byte that is not a printable CP865 char in SJ3 }
      #195..#224, #226..#244 : exit(false);

      { if there was no UTF-8 codepoint initial byte already then any extended ASCII char indicates CP865 }
      #128..#194, #245..#255 : exit(true);

      { otherwise keep checking next bytes... }
    end;
  end;
end;

function ConvertToUTF8(s : string): UTF8String;
const ArrayCP865ToUTF8 : TCharToUTF8Table = (
  'Ç', // #128
  'ü', // #129
  'é', // #130
  'â', // #131
  'ä', // #132
  'à', // #133
  'å', // #134
  'ç', // #135
  'ê', // #136
  'ë', // #137
  'è', // #138
  'ï', // #139
  'î', // #140
  'ì', // #141
  'Ä', // #142
  'Å', // #143
  'É', // #144
  'æ', // #145
  'Æ', // #146
  'ô', // #147
  'ö', // #148
  'ò', // #149
  'û', // #150
  'ù', // #151
  'ÿ', // #152
  'Ö', // #153
  'Ü', // #154
  'ø', // #155
  '£', // #156
  'Ø', // #157
  '₧', // #158
  'ƒ', // #159
  'á', // #160
  'í', // #161
  'ó', // #162
  'ú', // #163
  'ñ', // #164
  'Ñ', // #165
  'ª', // #166
  'º', // #167
  '¿', // #168
  '⌐', // #169
  '¬', // #170
  'm', // #171 { exception due to old SJ3 logic ! }
  '¼', // #172
  '¡', // #173
  '«', // #174
  '¤', // #175
  '░', // #176
  '▒', // #177
  '▓', // #178
  '│', // #179
  '┤', // #180
  '╡', // #181
  '╢', // #182
  '╖', // #183
  '╕', // #184
  '╣', // #185
  '║', // #186
  '╗', // #187
  '╝', // #188
  '╜', // #189
  '╛', // #190
  '┐', // #191
  '└', // #192
  '┴', // #193
  '┬', // #194
  '├', // #195
  '─', // #196
  '┼', // #197
  '╞', // #198
  '╟', // #199
  '╚', // #200
  '╔', // #201
  '╩', // #202
  '╦', // #203
  '╠', // #204
  '═', // #205
  '╬', // #206
  '╧', // #207
  '╨', // #208
  '╤', // #209
  '╥', // #210
  '╙', // #211
  '╘', // #212
  '╒', // #213
  '╓', // #214
  '╫', // #215
  '╪', // #216
  '┘', // #217
  '┌', // #218
  '█', // #219
  '▄', // #220
  '▌', // #221
  '▐', // #222
  '▀', // #223
  'α', // #224
  'ß', // #225
  'Γ', // #226
  'π', // #227
  'Σ', // #228
  'σ', // #229
  'μ', // #230
  'τ', // #231
  'Φ', // #232
  'Θ', // #233
  'Ω', // #234
  'δ', // #235
  '∞', // #236
  'φ', // #237
  'ε', // #238
  '∩', // #239
  '≡', // #240
  '±', // #241
  '≥', // #242
  '≤', // #243
  '⌠', // #244
  '⌡', // #245
  '÷', // #246
  '≈', // #247
  '°', // #248
  '∙', // #249
  '·', // #250
  '√', // #251
  'ⁿ', // #252
  '²', // #253
  '■', // #254
  ' '  // #255
);
var i, l : integer;
    tmp : UTF8String;
begin
  tmp := '';
  if IsCP865(s) then
    begin
      l := Length(s);
      for i:=1 to l do
      begin
        if s[i] > #127 then
          tmp += ArrayCP865ToUTF8[s[i]]
        else
          tmp += s[i];
      end;
      ConvertToUTF8 := tmp;
    end
  else
    ConvertToUTF8 := s;
end;

end.

