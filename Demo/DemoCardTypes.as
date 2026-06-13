// DemoCardTypes.as - Shared types for Demo Dashboard cards
//
// CardItem: common data item used by donut charts and table cards.
// Callback funcdefs: shared signatures for item click, color toggle, and shuffle.

funcdef void CardItemClickCallback(int index, const string&in label);
funcdef void CardColorCallback();
funcdef void CardShuffleCallback();

class CardItem
{
    string label;
    float  value;
    color  itemColor;

    CardItem() {}
    CardItem(const string&in _label, float _value, const color&in _color)
    {
        label = _label;
        value = _value;
        itemColor = _color;
    }
}
