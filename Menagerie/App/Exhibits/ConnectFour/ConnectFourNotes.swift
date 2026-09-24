extension ExhibitNotes {
    static let connectFour = ExhibitNotes(
        lede: "Claude's opponent is a game-tree search written from scratch. It packs the board into two 64-bit integers, examines millions of positions a second, and scores every column as it thinks.",
        sections: [
            Section(
                title: "A board in two integers",
                body: "Each position is two `UInt64`s in John Tromp's layout: seven bits per column, six for the rows plus an empty sentinel. Shifting by 1, 7, 6 or 8 moves every disc up, across or along a diagonal at once, so a few shifts and ANDs find every four in a row, or every empty cell that would complete one. Undo just restores the previous copy."
            ),
            Section(
                title: "Negamax with alpha-beta",
                body: "The engine searches the game tree with **negamax** and **alpha-beta** pruning, deepening one ply per iteration. A transposition table stores each position's bound, depth and best move, so a position reached again costs one lookup. The stored move goes first, then moves that create the most new threats, then central columns. Good ordering lets alpha-beta skip most of the tree."
            ),
            Section(
                title: "Never walk into a loss",
                body: "Following Pascal Pons, one bitboard expression finds the cells where the opponent would win. Two playable ones mean the game is lost, one must be blocked, and no disc goes directly beneath one. So the search never enters a position with a win on the spot. Positions with a single safe reply are searched a ply deeper, which settles forcing lines fast."
            ),
            Section(
                title: "Reading the chips",
                body: "Each chip scores a column for the player to move. **Win in 5** is a proof: a win by their fifth disc from now, whatever the replies. Plain numbers are heuristic: discs count the lines through their cells, and *threats*, empty cells that would complete a four, count more on the owner's row parity. Odd rows favor the first player, even rows the second."
            ),
            Section(
                title: "How hard Claude plays",
                body: "*Casual* looks four plies ahead and picks among the better moves at random. *Strong* searches up to twelve plies within half a second. *Ruthless* keeps deepening for 1.5 seconds with no depth limit, which often solves the game outright from the middle game on. Scores become exact once every line reaches its end, and the stats say when a position is solved."
            ),
        ]
    )
}
