---
description: Systematic code refactoring with technical debt cleanup and quality improvements
---

# Code Refactoring

Launch the **code-refactorer** agent to:

1. Identify code smells and SOLID violations
2. Optimize performance bottlenecks
3. Improve company isolation (company_uuid filtering)
4. Clean up technical debt
5. Preserve functionality (no behavior changes)
6. Use /commit skill for commits

## Refactoring Categories

**1. Code Smells**
- Long methods (>50 lines)
- Large classes (>500 lines)
- Duplicated code (DRY violations)
- Magic numbers/strings
- Complex conditionals (cyclomatic complexity >10)
- Dead code
- Inappropriate naming

**2. SOLID Violations**
- God classes (too many responsibilities)
- Tight coupling (hard dependencies)
- Interface bloat
- Fragile base classes
- Hardcoded dependencies

**3. Performance Optimizations**
- N+1 query problems
- Missing indexes
- Unnecessary allocations
- Inefficient LINQ queries
- Missing caching opportunities
- Synchronous I/O in async contexts

**4. Multi-Tenant Security**
- Missing company_uuid filters
- Hardcoded tenant references
- Shared resources without isolation
- Data leakage risks

**5. Architectural Improvements**
- Extract services from controllers
- Move business logic from repositories
- Introduce domain models
- Separate concerns
- Extract interfaces for testability

## When to Use

- Cleaning up technical debt
- Before major refactoring
- After identifying code smells
- Improving code quality metrics
- Performance optimization needed

## Example Usage

```
/refactor services/ai-engine/Services/GuideSelectionService.cs
```

or

```
/refactor AI-72
```

## Agent Will

1. Read file(s) or Jira tech-debt task
2. Analyze for code smells and violations
3. Identify refactoring opportunities
4. Preserve existing tests (run before changes)
5. Apply refactorings incrementally
6. Run tests after each change
7. Verify functionality preserved
8. Check performance impact
9. Stage changes
10. Prepare commit summary
11. **Use /commit skill** to create commit
12. Update Jira if applicable

## Safety Checks

- ✅ Tests exist before refactoring (or create tests first)
- ✅ Tests pass before changes
- ✅ Tests pass after changes
- ✅ No functionality changes (external behavior same)
- ✅ Performance not regressed
- ✅ Code coverage maintained or improved

## Refactoring Report Includes

- Refactoring category (code smell, SOLID, performance, security, architecture)
- Files modified with line counts (before/after)
- What was improved
- Test results (passed/coverage)
- Performance impact (if applicable)
- Breaking changes (should be rare/none)
- Commit summary prepared
- Next refactoring opportunities

## Example Refactorings

**Extract Method:**
```csharp
// Before: Long method with multiple responsibilities
public async Task<Result> ProcessTicket(Ticket ticket) {
    // 100 lines of mixed logic...
}

// After: Extracted focused methods
public async Task<Result> ProcessTicket(Ticket ticket) {
    await ValidateTicket(ticket);
    var classification = await ClassifyTicket(ticket);
    return await RouteTicket(ticket, classification);
}
```

**Extract Service:**
```csharp
// Before: Controller with business logic
public class TicketsController {
    public async Task<IActionResult> Create(CreateTicketDto dto) {
        // Business logic here...
    }
}

// After: Service layer
public class TicketsController {
    private readonly ITicketService _ticketService;

    public async Task<IActionResult> Create(CreateTicketDto dto) {
        var result = await _ticketService.CreateTicket(dto);
        return Ok(result);
    }
}
```

## Next Steps

After refactoring:
- Tests verified passing
- Commit created (via /commit skill)
- Code quality improved
- Continue with next refactoring or `/qa-backend` / `/qa-frontend`
