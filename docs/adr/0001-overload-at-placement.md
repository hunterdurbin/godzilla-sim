# Overload is performed when a card is placed, not at the check timing

The rules make Overload a non-interrupt rule action, performed at a check timing (11.5, 10.4.3.1). Even so, the engine destroys a zone's old stack at the moment a new card is placed into that zone. Zones are modelled as stacks, and that is why. A zone holding a newly placed card on top of the card it overloads would look exactly like an evolution or stack-on-play stack. So the "overloaded, waiting for the check timing" state cannot be represented without a per-card marker that every zone query would have to respect.

The approximation differs from the rules only while the current effect is still resolving. For that window, the overloaded card has already left play instead of staying until the check timing. Overload still counts as \<Destroy\> (5.12.1.1, 11.5.1): Replacement effects apply and "whenever … is destroyed" watchers trigger. It never triggers \<Revenge\> (12.7.2).

**Consequences:** the check-timing rule-action loop has no Overload step. Do not add an empty one, and do not "fix" this to defer Overload unless zones gain a representation for unstacked cards.
