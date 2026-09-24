/// Stopword lists: the function words and filler that carry little meaning on
/// their own, used to split text into candidate key phrases and to ignore
/// noise when comparing sentences.
public enum ProseStopwords {
    /// Common English function words, auxiliaries, pronouns, quantifiers and
    /// discourse words, in lowercase with straight apostrophes. Content words
    /// are left out on purpose, even very frequent ones, so that phrases such
    /// as "considered types" survive keyword extraction.
    public static let english: Set<String> = [
        "a", "about", "above", "according", "across", "actually", "after", "afterwards", "again",
        "against", "ago", "ah", "all", "almost", "alone", "along", "already", "also", "although",
        "always", "am", "among", "amongst", "an", "and", "another", "any", "anybody", "anyhow",
        "anyone", "anything", "anyway", "anywhere", "apart", "are", "aren't", "around", "as",
        "aside", "at", "away", "back", "barely", "be", "became", "because", "become", "becomes",
        "becoming", "been", "before", "beforehand", "behind", "being", "below", "beside",
        "besides", "between", "beyond", "both", "but", "by", "came", "can", "can't", "cannot",
        "certainly", "clearly", "come", "comes", "could", "couldn't", "did", "didn't", "do",
        "does", "doesn't", "doing", "don't", "done", "down", "during", "each", "e.g", "eg",
        "eight", "either", "else", "elsewhere", "enough", "especially", "etc", "even", "ever",
        "every", "everybody", "everyone", "everything", "everywhere", "exactly", "except",
        "fairly", "far", "few", "fifth", "first", "five", "for", "former", "formerly", "four",
        "fourth", "from", "further", "furthermore", "get", "gets", "getting", "give", "given",
        "gives", "go", "goes", "going", "gone", "got", "gotten", "had", "hadn't", "hardly", "has",
        "hasn't", "have", "haven't", "having", "he", "he'd", "he'll", "he's", "hence", "her",
        "here", "here's", "hereby", "herein", "hers", "herself", "him", "himself", "his", "how",
        "how's", "however", "i", "i'd", "i'll", "i'm", "i've", "i.e", "ie", "if", "in", "indeed",
        "instead", "into", "is", "isn't", "it", "it'd", "it'll", "it's", "its", "itself", "just",
        "keep", "keeps", "kept", "last", "lately", "later", "latter", "least", "less", "let",
        "let's", "like", "likely", "made", "mainly", "make", "makes", "many", "may", "maybe", "me",
        "meanwhile", "merely", "might", "mine", "more", "moreover", "most", "mostly", "much",
        "must", "mustn't", "my", "myself", "namely", "nearly", "neither", "never", "nevertheless",
        "next", "nine", "no", "nobody", "none", "noone", "nor", "not", "nothing", "now", "nowhere",
        "of", "off", "often", "oh", "ok", "okay", "on", "once", "one", "ones", "only", "onto", "or",
        "other", "others", "otherwise", "ought", "our", "ours", "ourselves", "out", "over",
        "overall", "own", "per", "perhaps", "please", "plus", "pretty", "probably", "quite",
        "rather", "really", "regarding", "said", "same", "say", "saying", "says", "second",
        "see", "seem", "seemed", "seeming", "seems", "seen", "seven", "several", "shall",
        "shan't", "she", "she'd", "she'll", "she's", "should", "shouldn't", "simply", "since",
        "six", "so", "some", "somebody", "somehow", "someone", "something", "sometime",
        "sometimes", "somewhat", "somewhere", "soon", "still", "such", "sure", "take", "taken",
        "takes", "ten", "than", "that", "that's", "the", "their", "theirs", "them", "themselves",
        "then", "thence", "there", "there's", "thereafter", "thereby", "therefore", "therein",
        "these", "they", "they'd", "they'll", "they're", "they've", "thing", "things", "third",
        "this", "those", "though", "three", "through", "throughout", "thru", "thus", "to",
        "together", "too", "took", "toward", "towards", "truly", "twice", "two", "under",
        "unless", "until", "unto", "up", "upon", "us", "use", "used", "uses", "using", "usually",
        "very", "via", "was", "wasn't", "way", "we", "we'd", "we'll", "we're", "we've", "well",
        "went", "were", "weren't", "what", "what's", "whatever", "when", "when's", "whenever",
        "where", "where's", "whereas", "whereby", "wherein", "wherever", "whether", "which",
        "while", "who", "who's", "whoever", "whole", "whom", "whose", "why", "why's", "will",
        "with", "within", "without", "won't", "would", "wouldn't", "yes", "yet", "you", "you'd",
        "you'll", "you're", "you've", "your", "yours", "yourself", "yourselves",
    ]
}
