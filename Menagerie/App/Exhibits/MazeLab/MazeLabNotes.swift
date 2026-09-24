extension ExhibitNotes {
    static let mazeLab = ExhibitNotes(
        lede: "Carve a maze with a classic algorithm, then set a search loose inside it. Every explored cell is colored by the moment it was expanded, so the shape of the flood shows how each algorithm thinks.",
        sections: [
            .init(
                title: "Carving perfect mazes",
                body: "A *perfect* maze is a spanning tree: exactly one route joins any two cells. The **recursive backtracker** digs depth-first with a stack, leaving long corridors. **Prim's** grows from a random frontier and turns bushy. **Kruskal's** removes walls in random order, and union–find vetoes any removal that would close a loop. **Wilson's** loop-erased random walks make every possible maze equally likely."
            ),
            .init(
                title: "Loops and mud",
                body: "A perfect maze leaves a search nothing to choose between, so **Loops** knocks through a share of the dead ends, and each one closes a cycle. **Mud** costs `5` to cross instead of `1`. Breadth-first search counts only steps and wades straight through. Dijkstra and A* weigh cost and detour around it. The comparison shows where *fewest steps* and *cheapest route* part ways."
            ),
            .init(
                title: "Searching blind",
                body: "**BFS** takes cells from a first-in, first-out queue, so it spreads in rings and finds the fewest steps. **DFS** uses a stack and dives down one corridor at a time. It always finds *a* path, often an absurd one. **Bidirectional BFS** grows two rings, one from each end, and stops when they touch. Each ring needs only half the radius."
            ),
            .init(
                title: "Searching with a hint",
                body: "**Dijkstra** keeps its frontier in a binary heap ordered by cost so far, `g`. **A*** orders by `g + h`, where `h` is the Manhattan distance to the goal. Every step costs at least 1, so `h` never overestimates, and A* still finds the cheapest route. Ties go to the larger `g`, which keeps the frontier narrow. **Greedy best-first** trusts `h` alone: fast, and easily fooled."
            ),
            .init(
                title: "Painting live",
                body: "Every stroke re-runs the search from scratch. On a few thousand cells, even running all six solvers takes under a millisecond, so the route and the comparison redraw as fast as you paint. Strokes follow a four-connected line, which keeps painted walls watertight however fast you drag."
            ),
        ]
    )
}
