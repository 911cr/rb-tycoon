---
description: Create premium UX design specifications with WCAG AA accessibility
---

# UX Design

Launch the **ui-design-ux** agent to:

1. Understand user needs and pain points
2. Design for MSP user personas (Technician/Manager/End Client)
3. Create design specifications with MUI components
4. Ensure WCAG AA accessibility compliance
5. Design responsive layouts (mobile/tablet/desktop)
6. Specify interactions and animations (60fps)
7. Prepare handoff for frontend-developer

## What You'll Get

- Design specification document: `docs/plan/{plan-id}/design/{feature-name}-design-spec.md`
- User flow diagrams
- Component hierarchy breakdown
- Visual design specs (colors, spacing, typography)
- MUI component selections and customizations
- Accessibility checklist (ARIA, keyboard nav, contrast)
- Responsive breakpoint specifications
- Animation specifications (duration, easing, triggers)
- Interaction states (hover, focus, active, disabled)
- Implementation notes for frontend-developer

## Design Handoff Includes

1. **User Flows**: Step-by-step user journey
2. **Component Breakdown**: Atomic design hierarchy
3. **Visual Specs**: Colors, spacing, typography, shadows
4. **MUI Components**: Which components to use, customizations
5. **Accessibility**: WCAG AA checklist, keyboard navigation, screen readers
6. **Responsive Design**: Mobile/tablet/desktop layouts
7. **Interactions**: Hover, focus, click, drag, animations
8. **Implementation Notes**: Technical guidance for frontend-developer

## When to Use

- Starting a new UI feature or page
- Redesigning existing interfaces
- Need UX improvements for existing feature
- Planning user experience before implementation
- Accessibility improvements needed

## Example Usage

```
/design-ux AI-68 notification delivery UI
```

## Agent Will

1. Read Jira task requirements
2. Analyze user personas impacted
3. Research design patterns and best practices
4. Create design specification document
5. Include accessibility guidelines
6. Specify MUI components and customizations
7. Save spec to `docs/plan/{plan-id}/design/`
8. Update Jira with design spec link
9. Add label `design-ready`
10. Mark Jira as "Ready for Development"

## Next Steps

After design approval:
- `/implement-jira-task AI-XXX` - Implement the design task
- Or use `/act` to implement from plan
- Jira task will be routed to frontend-developer agent
