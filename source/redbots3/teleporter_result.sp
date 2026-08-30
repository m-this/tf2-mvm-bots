/* The one function of the teleporter behaviour the generator cannot write

Everything else is generated from internal/action/engineerbuildteleporter. This copies into a
buffer its caller sized, and a generated function has no way to see that length: what it writes is
the size of its own declaration, which would overrun a caller who passed something smaller.

mvm-z83 carries the gap. When it closes this goes away. */

void EngineerTeleporter_LastResult(int actor, char[] buffer, int maxlength)
{
	strcopy(buffer, maxlength, m_sTeleporterLastResult[actor][0] == '\0' ? "nothing yet" : m_sTeleporterLastResult[actor]);
}
