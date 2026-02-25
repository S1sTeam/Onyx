package dev.onyx.core.i18n;

import java.text.MessageFormat;
import java.util.Locale;
import java.util.MissingResourceException;
import java.util.ResourceBundle;

public final class I18n {
    private final ResourceBundle bundle;

    private I18n(ResourceBundle bundle) {
        this.bundle = bundle;
    }

    public static I18n load(String localeCode) {
        Locale locale = parseLocale(localeCode);
        try {
            return new I18n(ResourceBundle.getBundle("messages", locale));
        } catch (MissingResourceException ignored) {
            return new I18n(ResourceBundle.getBundle("messages", Locale.ENGLISH));
        }
    }

    public String t(String key, Object... args) {
        String pattern;
        try {
            pattern = bundle.getString(key);
        } catch (MissingResourceException ignored) {
            pattern = key;
        }
        return MessageFormat.format(pattern, args);
    }

    private static Locale parseLocale(String localeCode) {
        if (localeCode == null || localeCode.isBlank()) {
            return Locale.ENGLISH;
        }
        String sanitized = localeCode.trim().replace('_', '-');
        Locale locale = Locale.forLanguageTag(sanitized);
        if (locale.getLanguage().isBlank()) {
            return Locale.ENGLISH;
        }
        return locale;
    }
}
