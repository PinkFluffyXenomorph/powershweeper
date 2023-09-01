param (
  # size of the board, clamped between SEE BELOW
  # default val: 10
  [int]$boardSize = 10,

  # mine density, clamped between SEE BELOW 
  # default val: 15%
  [int]$mineDensity = 15,

  # if a number is passed into the seed the same 
  # board will be played each restart for the session 
  [int]$seed
)

#region: validate and clamp params
$MIN_SIZE = 5;
# max size above 20 becomes unbearably slow, input lags behind due to slow redrawing
$MAX_SIZE = 20;
$MIN_MINE_DENSITY = 5;
$MAX_MINE_DENSITY = 75;

if ($boardSize -le $MIN_SIZE) {
  $boardSize = $MIN_SIZE;
}
elseif ($boardSize -ge $MAX_SIZE) {
  $boardSize = $MAX_SIZE;
}

if ($mineDensity -le $MIN_MINE_DENSITY) {
  $mineDensity = $MIN_MINE_DENSITY;
}
elseif ($mineDensity -ge $MAX_MINE_DENSITY) {
  $mineDensity = $MAX_MINE_DENSITY;
} 
#endregion

#region: special characters for Virtual Terminal Sequence magic
$ESC = "[";
$HIDE_CURSOR = "${ESC}?25l";
$SHOW_CURSOR = "${ESC}?25h";
# text formatting:
$RESET = "${ESC}0m";
$BOLD = "${ESC}1m";
$UNBOLD = "${ESC}22m";
$UNDERSCORE = "${ESC}4m";
#endregion

#region: outputting/printing to console
function WriteChars($character) {
  Write-Host -NoNewLine $character;
}

function drawBoard {
  for ($row = 0; $row -lt $boardSize; $row++) {
    for ($col = 0; $col -lt $boardSize; $col++) {
      drawCell $row $col;
    }
    WriteChars "`n";
  }
}

function updateBoard {
  # move the terminal cursor up and left
  WriteChars "${ESC}${boardSize}A";
  WriteChars "${ESC}$($boardSize * 3)D";
  # redraw the updated board
  drawBoard;
}

function drawCell ($row, $col) {
  $cellState = getCellState $row $col;
  $mineData = getMineState $row $col;
  
  $charToWrite;
  # cell not yet visited
  if ($cellState -eq $null) {
    $charToWrite = ".";
  }
  # cell has been visited
  elseif ($cellState -eq 1) {
    # draw it as empty if no neighbors
    if ($mineData -eq 0) {
      $charToWrite = " ";
    }
    # draw the mine
    elseif ($mineData -eq 9) {
      $charToWrite = "@";
    }
    # write the number of neighboring mines
    else {
      $charToWrite = $mineData;
    }
  }
  # cell is flagged
  elseif ($cellState -eq 2) {
    $charToWrite = "%";
  }
  # wrap the cursor around it
  if ($script:cursor_row -eq $row -and $script:cursor_col -eq $col) {
    WriteChars("[${charToWrite}]");
  }
  else {
    WriteChars(" ${charToWrite} ");
  }
}
#endregion

#region: game processing
Function startGame {
  WriteChars "`n";
  $script:cells = New-Object "object[,]" $boardSize, $boardSize;
  $script:mines = New-Object "object[,]" $boardSize, $boardSize;

  # set/reset cursor position
  $script:cursor_row = 0;
  $script:cursor_col = 0;

  if ($seed) {
    Get-Random -SetSeed $seed | Out-Null; # nullify the output so its not printed
  }
  
  setMines;
  drawBoard;
}

Function gameOver {
  for ($row = 0; $row -lt $boardSize; $row++) {
    for ($col = 0; $col -lt $boardSize; $col++) {
      # uncover all mines
      if ($(getMineState $row $col) -eq 9) {
        $script:cells[$row, $col] = 1;
      }
    }
  }
  updateBoard;
  WriteChars "`nGame over! :c`n";
  askForRestart;
}

Function quit {
  WriteChars $SHOW_CURSOR;
  $script:running = $false;
}

Function checkIfVictory {
  $victory = $true;
  for ($row = 0; $row -lt $boardSize; $row++) {
    for ($col = 0; $col -lt $boardSize; $col++) {
      $mineData = getMineState $row $col;
      # if not mine and flagged -> break (not mine & flagged)
      # if mine and unflagged -> break (mine & not flagged)
      # if checked all and didn't break -> victory
      if ($(getMineState $row $col) -ne 9) {
        if ($(getCellState $row $col) -eq 2) {
          $victory = $false; 
          break
        }
        continue;
      }
      if ($(getCellState $row $col) -ne 2) {
        $victory = $false;
        break;
      }
    }
  }
  
  if ($victory) {
    # one last update after revealing all mines
    updateBoard;
    WriteChars "`nYou've won!`n";
    askForRestart;
  }
}

Function setMines {
  $minePerc = $mineDensity / 100;
  $mineCount = [Math]::Round($boardSize * $boardSize * $minePerc);
  while ($mineCount -gt 0) {
    $row = Get-Random -minimum 0 -maximum $boardSize;
    $col = Get-Random -minimum 0 -maximum $boardSize;
    # 9 means its a mine
    if ($script:mines[$row, $col] -ne 9) {
      $script:mines[$row, $col] = 9;
      $mineCount--;
    }
  }
  # count mines in neighboring cells and save that info in the mine matrix
  for ($row = 0; $row -lt $boardSize; $row++) {
    for ($col = 0; $col -lt $boardSize; $col++) {
      if ($script:mines[$row, $col] -ne 9) {
        $script:mines[$row, $col] = countNeighbors $row $col;
      }
    }
  }
}

Function getCellState ($row, $col) {
  return $script:cells[$row, $col];
}

Function getMineState ($row, $col) {
  return $script:mines[$row, $col];
}

Function uncoverCell ($row, $col) {
  $cellState = getCellState $row $col;
  $mineData = getMineState $row $col;

  if ($mineData -eq 9) {
    gameOver;
  }
  # also uncover neighbors if no mines in neighboring cells
  # recursively reveal all neighboring 0s
  elseif ($mineData -eq 0 -and $cellState -eq $null) {
    # mark as visited so the neighbors check doesn't visit this again
    $script:cells[$row, $col] = 1;

    for ($offsetRow = -1; $offsetRow -le 1; $offsetRow++) {
      for ($offsetCol = -1; $offsetCol -le 1; $offsetCol++) {
        $neighborRow = $($row + $offsetRow);
        $neighborCol = $($col + $offsetCol);
        if ($neighborRow -eq $row -and $neighborCol -eq $col) {
          continue;
        }
        if ($neighborRow -lt 0 -or $neighborRow -gt $($boardSize - 1) -or $neighborCol -lt 0 -or $neighborCol -gt $($boardSize - 1)) {
          continue;
        }
        uncoverCell $neighborRow $neighborCol;
      }
    }
  }
  # only uncover unvisited and unflagged cells
  elseif ($cellState -ne 2) {
    $script:cells[$row, $col] = 1;
  }
}

Function flagCell ($row, $col) {
  $cellState = getCellState $row $col;
  if ($cellState -eq 2) {
    $script:cells[$row, $col] = $null;
  }
  elseif ($cellState -eq $null) {
    $script:cells[$row, $col] = 2;
    # check for victory if someone blindly stabs at the mines :o
    checkIfVictory;
  }
}

Function countNeighbors ($row, $col) {
  $mineCount = 0;
  for ($offsetRow = -1; $offsetRow -le 1; $offsetRow++) {
    for ($offsetCol = -1; $offsetCol -le 1; $offsetCol++) {
      $finalRow = $($row + $offsetRow);
      $finalCol = $($col + $offsetCol);
      # exclude counting self
      if ($finalRow -eq $row -and $finalCol -eq $col) {
        continue;
      }
      # edges boundary check
      if ($finalRow -lt 0 -or $finalRow -gt $($boardSize - 1) -or $finalCol -lt 0 -or $finalCol -gt $($boardSize - 1)) {
        continue;
      }
      if ($(getMineState $finalRow $finalCol) -eq 9) {
        $mineCount++;
      }
    }
  }
  return $mineCount;
}
#endregion

#region: input
function processPressedKey {
  $key = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown");
  $key = $key.VirtualKeyCode;

  # Q
  if ($key -eq 81) {
    quit;
  }
  # R
  if ($key -eq 82) {
    askForRestart;
  }
  # F
  elseif ($key -eq 70) {
    flagCell $script:cursor_row $script:cursor_col;
  }
  # ARROW UP or W
  elseif ($key -eq 38 -or $key -eq 87) {
    moveUp;
  }
  # ARROW DOWN or S
  elseif ($key -eq 40 -or $key -eq 83) {
    moveDown;
  }
  # ARROW LEFT or A
  elseif ($key -eq 37 -or $key -eq 65) {
    moveLeft;
  }
  # ARROW RIGHT or D
  elseif ($key -eq 39 -or $key -eq 68) {
    moveRight;
  }
  # SPACE or ENTER
  elseif ($key -eq 32 -or $key -eq 13) {
    uncoverCell $script:cursor_row $script:cursor_col;
  }
}

function askForRestart {
  $restart = Read-Host "`nDo you want to start a new game? (y/n)";
  if ($restart -eq "y") {
    startGame;
  }
  elseif ($restart -eq "n") {
    quit;
  }
  else {
    WriteChars "Unknown answer, try again`n";
    askForRestart;
  }
}

function moveUp {
  if ($script:cursor_row -gt 0) {
    $script:cursor_row--;
  }
}
function moveDown {
  if ($script:cursor_row -lt $($boardSize - 1)) {
    $script:cursor_row++;
  }
}
function moveLeft {
  if ($script:cursor_col -gt 0) {
    $script:cursor_col--;
  }
}
function moveRight {
  if ($script:cursor_col -lt $($boardSize - 1)) {
    $script:cursor_col++;
  }
}
#endregion

#region: initial setup and gameloop
WriteChars $HIDE_CURSOR;
startGame;
$script:running = $true;

while ($script:running) {
  updateBoard;
  processPressedKey;
}
#endregion