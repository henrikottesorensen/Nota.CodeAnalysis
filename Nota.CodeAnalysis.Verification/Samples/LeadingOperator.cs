namespace Nota.Verification;

/// <summary>
/// An operator leading a wrapped line, which NOTA0002 reports, asserted by verify.sh.
///
/// The second method wraps the same expression the way the rule wants, and must stay quiet - from
/// NOTA0002 and from StyleCop alike, since a rule whose fix another rule reports is a loop rather
/// than a convention.
/// </summary>
public static class LeadingOperator
{
    /// <summary>The operator leads the second line.</summary>
    /// <param name="a">The first operand.</param>
    /// <param name="b">The second operand.</param>
    /// <returns>Both.</returns>
    public static bool Leading(bool a, bool b)
    {
        return a
            && b;
    }

    /// <summary>The operator ends the first line.</summary>
    /// <param name="a">The first operand.</param>
    /// <param name="b">The second operand.</param>
    /// <returns>Both.</returns>
    public static bool Trailing(bool a, bool b)
    {
        return a &&
            b;
    }
}
