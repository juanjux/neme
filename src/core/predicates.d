module neme.core.predicates;

import neme.core.types;

@safe public pure pragma(inline)
bool All(const scope Subject s) { return true; }

@safe public pure pragma(inline)
bool None(const scope Subject s) { return false; }

@safe public pure pragma(inline)
bool Empty(const scope Subject s) { return s.text.length == 0; }

@safe public pure pragma(inline)
bool NotEmpty(const scope Subject s) { return s.text.length > 0; }
