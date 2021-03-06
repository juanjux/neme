module neme.core.predicates;

import neme.core.types;

@safe public pure pragma(inline)
bool All(in Subject _) { return true; }

@safe public pure pragma(inline)
bool None(in Subject _) { return false; }

@safe public pure pragma(inline)
bool Empty(in Subject s) { return s.text.length == 0; }

@safe public pure pragma(inline)
bool NotEmpty(in Subject s) { return s.text.length > 0; }
