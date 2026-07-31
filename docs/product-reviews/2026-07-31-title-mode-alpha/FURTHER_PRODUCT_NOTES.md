
### TLAR-010 - List behaves as continous

**Observed**

When starting from the top most item on the list, and clicking **Shift + Tab**, the circeled item, becomes the lowest item on the list. 
This means the current List behaves like a Circular DLL.

**Requiered Geometry**
The List is supposed to be linear - uncircular. 
When trying to go up form the top most element the selected element should remain unchanged. 
When Trying to move further down form the lowest element the selected element should remain unchanged as well.

**Acceptance Criteria**
When the top most element is circeled, and the user presses **Shift + Tab**
the circled element should remain unchanged and the list doesnt change.
When the lowest element on the list is circeled, and the user presses
**Tab** the circeled element should remain there.