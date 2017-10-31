module neme.core.predicates;

import neme.core.types;

@safe public pure pragma(inline)
bool All(scope Subject s) { return true; }

@safe public pure pragma(inline)
bool None(scope Subject s) { return false; }

@safe public pure pragma(inline)
bool Empty(scope Subject s) { return s.text.length == 0; }

@safe public pure pragma(inline)
bool NotEmpty(scope Subject s) { return s.text.length > 0; }
